import type { EntityType } from './keys.js';

/** A record as it travels over the wire and sits in DynamoDB. */
export interface StoredRecord {
  entityType: EntityType;
  id: string;
  updatedAt: string;
  /** Soft delete. A hard delete would be resurrected by the next snapshot. */
  deleted: boolean;
  body: Record<string, unknown>;
}

export interface SnapshotPage {
  records: StoredRecord[];
  nextCursor?: string;
  hasMore: boolean;
}

/**
 * Persistence behind an interface so handlers can be tested without DynamoDB.
 *
 * Every method takes the accountId as its first argument, and implementations build
 * the partition key from it. Handlers obtain that id only from the verified token
 * (src/auth/account.ts), so there is no path by which a request reaches another
 * account's partition.
 */
export interface Store {
  put(accountId: string, record: StoredRecord): Promise<void>;
  softDelete(
    accountId: string,
    entityType: EntityType,
    id: string,
    croppingId: string | undefined,
    updatedAt: string,
  ): Promise<void>;
  snapshot(
    accountId: string,
    options: { cursor?: string; since?: string; limit?: number },
  ): Promise<SnapshotPage>;
  deleteAccount(accountId: string): Promise<void>;
}
