/**
 * DynamoDB key construction. research.md R7.
 *
 * Single table, partitioned by account:
 *   PK = ACCOUNT#<cognito sub>
 *   SK = entity-specific
 *
 * Partitioning this way makes FR-062 structural rather than procedural: a request
 * cannot reach another account's data, because the partition key is built from the
 * verified token and the token is the only source of the account id.
 */

export type EntityType =
  | 'field'
  | 'cropping'
  | 'variety'
  | 'fertilizerTemplate'
  | 'scheduledApplication'
  | 'expense'
  | 'harvest'
  | 'sale';

export const ENTITY_TYPES: readonly EntityType[] = [
  'field',
  'cropping',
  'variety',
  'fertilizerTemplate',
  'scheduledApplication',
  'expense',
  'harvest',
  'sale',
];

export function partitionKey(accountId: string): string {
  return `ACCOUNT#${accountId}`;
}

/**
 * The sort key for one record.
 *
 * Records belonging to a cropping are prefixed with it so the whole cropping can be
 * read with one `begins_with` query (research.md R7).
 */
export function sortKey(
  entityType: EntityType,
  id: string,
  croppingId?: string,
): string {
  switch (entityType) {
    case 'field':
      return `FIELD#${id}`;
    case 'cropping':
      return `CROP#${id}`;
    case 'variety':
      return `VARIETY#${id}`;
    case 'fertilizerTemplate':
      return `TEMPLATE#${id}`;
    case 'scheduledApplication':
      return `CROP#${requireCropping(croppingId, entityType)}#APP#${id}`;
    case 'expense':
      return `CROP#${requireCropping(croppingId, entityType)}#EXP#${id}`;
    case 'harvest':
      return `CROP#${requireCropping(croppingId, entityType)}#HARVEST`;
    case 'sale':
      return `CROP#${requireCropping(croppingId, entityType)}#SALE#${id}`;
  }
}

function requireCropping(croppingId: string | undefined, entityType: EntityType): string {
  if (!croppingId) {
    throw new Error(`${entityType} requires a croppingId to build its sort key`);
  }
  return croppingId;
}

export function isEntityType(value: unknown): value is EntityType {
  return typeof value === 'string' && ENTITY_TYPES.includes(value as EntityType);
}
