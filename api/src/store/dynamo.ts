import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
} from '@aws-sdk/lib-dynamodb';

import type { EntityType } from './keys.js';
import { partitionKey, sortKey } from './keys.js';
import type { SnapshotPage, StoredRecord, Store } from './types.js';

/**
 * DynamoDB-backed Store. research.md R2, R7.
 *
 * Note what is NOT here: any way to pass an account id in from the caller other
 * than the first argument, which handlers populate only from the verified JWT claim
 * (src/auth/account.ts). The partition key is built here, from that value.
 */
export class DynamoStore implements Store {
  constructor(
    private readonly tableName: string,
    private readonly client: DynamoDBDocumentClient = DynamoDBDocumentClient.from(
      new DynamoDBClient({}),
    ),
  ) {}

  async put(accountId: string, record: StoredRecord): Promise<void> {
    const croppingId = record.body['croppingId'] as string | undefined;
    await this.client.send(
      new PutCommand({
        TableName: this.tableName,
        Item: {
          PK: partitionKey(accountId),
          SK: sortKey(record.entityType, record.id, croppingId),
          entityType: record.entityType,
          id: record.id,
          updatedAt: record.updatedAt,
          deleted: record.deleted,
          body: record.body,
        },
      }),
    );
  }

  async softDelete(
    accountId: string,
    entityType: EntityType,
    id: string,
    croppingId: string | undefined,
    updatedAt: string,
  ): Promise<void> {
    // Soft delete: a hard delete would be resurrected by the next snapshot, because
    // the snapshot has no way to know the record ever existed (sync-protocol.md I4).
    await this.client.send(
      new PutCommand({
        TableName: this.tableName,
        Item: {
          PK: partitionKey(accountId),
          SK: sortKey(entityType, id, croppingId),
          entityType,
          id,
          updatedAt,
          deleted: true,
          body: {},
        },
      }),
    );
  }

  async snapshot(
    accountId: string,
    options: { cursor?: string; since?: string; limit?: number },
  ): Promise<SnapshotPage> {
    const limit = options.limit ?? 100;
    const result = await this.client.send(
      new QueryCommand({
        TableName: this.tableName,
        KeyConditionExpression: '#pk = :pk',
        ExpressionAttributeNames: { '#pk': 'PK' },
        ExpressionAttributeValues: { ':pk': partitionKey(accountId) },
        Limit: limit,
        ...(options.cursor
          ? {
              ExclusiveStartKey: {
                PK: partitionKey(accountId),
                SK: options.cursor,
              },
            }
          : {}),
      }),
    );

    const items = (result.Items ?? []) as Array<StoredRecord & { SK: string }>;
    const records = items
      .filter((item) =>
        options.since ? item.updatedAt >= options.since : !item.deleted,
      )
      .map(({ entityType, id, updatedAt, deleted, body }) => ({
        entityType,
        id,
        updatedAt,
        deleted,
        body,
      }));

    const nextCursor = result.LastEvaluatedKey?.['SK'] as string | undefined;
    return {
      records,
      hasMore: nextCursor !== undefined,
      ...(nextCursor ? { nextCursor } : {}),
    };
  }

  async deleteAccount(accountId: string): Promise<void> {
    let cursor: string | undefined;
    do {
      const page = await this.snapshot(accountId, {
        ...(cursor ? { cursor } : {}),
        since: '0000',
        limit: 100,
      });
      for (const record of page.records) {
        await this.client.send(
          new DeleteCommand({
            TableName: this.tableName,
            Key: {
              PK: partitionKey(accountId),
              SK: sortKey(
                record.entityType,
                record.id,
                record.body['croppingId'] as string | undefined,
              ),
            },
          }),
        );
      }
      cursor = page.nextCursor;
    } while (cursor);
  }
}
