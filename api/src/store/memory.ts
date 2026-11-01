import type { EntityType } from './keys.js';
import { partitionKey, sortKey } from './keys.js';
import type { SnapshotPage, StoredRecord, Store } from './types.js';

/**
 * In-memory Store for tests.
 *
 * Keys are built exactly as the DynamoDB implementation builds them, so the
 * isolation test (FR-062) exercises the same partitioning the real store uses.
 */
export class MemoryStore implements Store {
  private readonly items = new Map<string, Map<string, StoredRecord>>();

  private partition(accountId: string): Map<string, StoredRecord> {
    const pk = partitionKey(accountId);
    let partition = this.items.get(pk);
    if (!partition) {
      partition = new Map();
      this.items.set(pk, partition);
    }
    return partition;
  }

  async put(accountId: string, record: StoredRecord): Promise<void> {
    const croppingId = record.body['croppingId'] as string | undefined;
    const sk = sortKey(record.entityType, record.id, croppingId);
    this.partition(accountId).set(sk, { ...record });
  }

  async softDelete(
    accountId: string,
    entityType: EntityType,
    id: string,
    croppingId: string | undefined,
    updatedAt: string,
  ): Promise<void> {
    const sk = sortKey(entityType, id, croppingId);
    const partition = this.partition(accountId);
    const existing = partition.get(sk);
    partition.set(sk, {
      entityType,
      id,
      updatedAt,
      deleted: true,
      body: existing?.body ?? {},
    });
  }

  async snapshot(
    accountId: string,
    options: { cursor?: string; since?: string; limit?: number },
  ): Promise<SnapshotPage> {
    const limit = options.limit ?? 100;
    const all = [...this.partition(accountId).entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .filter(([sk]) => (options.cursor ? sk > options.cursor : true))
      .map(([, record]) => record)
      .filter((record) =>
        options.since
          ? record.updatedAt >= options.since
          : // A full restore returns live records only; `since` is a catch-up and
            // must include tombstones so deletions propagate.
            !record.deleted,
      );

    const page = all.slice(0, limit);
    const hasMore = all.length > limit;
    const lastKey = page.length
      ? sortKey(
          page[page.length - 1]!.entityType,
          page[page.length - 1]!.id,
          page[page.length - 1]!.body['croppingId'] as string | undefined,
        )
      : undefined;

    return {
      records: page,
      hasMore,
      ...(hasMore && lastKey ? { nextCursor: lastKey } : {}),
    };
  }

  async deleteAccount(accountId: string): Promise<void> {
    this.items.delete(partitionKey(accountId));
  }

  /** Test helper: total records held for an account. */
  countFor(accountId: string): number {
    return this.partition(accountId).size;
  }
}
