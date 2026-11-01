import { isEntityType } from '../store/keys.js';
import type { StoredRecord } from '../store/types.js';

export class ValidationFailed extends Error {
  readonly code = 'validation_failed';
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Server-side validation.
 *
 * The device owns calculation — it has to, because every figure must be produced
 * offline (plan.md). What the server owns is ownership and shape: it rejects records
 * that could not have come from a correct client, so one buggy app version cannot
 * write nonsense that every other version then reads back.
 *
 * Money is integer centavos and weight is integer grams. A float arriving here means
 * a client has broken SC-009, and it is rejected rather than stored.
 */
const INTEGER_FIELDS = [
  'amountCentavos',
  'pricePerKgCentavos',
  'costCentavos',
  'areaSqm',
  'totalWetGrams',
  'quantityGrams',
  'driedWeightGrams',
  'avgWetGramsPerSack',
  'ratePerHectareGrams',
  'actualQuantityGrams',
];

export function validateRecord(input: unknown): StoredRecord {
  if (input === null || typeof input !== 'object') {
    throw new ValidationFailed('Record must be an object');
  }
  const record = input as Record<string, unknown>;

  if (!isEntityType(record['entityType'])) {
    throw new ValidationFailed(`Unknown entityType: ${String(record['entityType'])}`);
  }
  const id = record['id'];
  if (typeof id !== 'string' || !UUID_RE.test(id)) {
    throw new ValidationFailed(
      'id must be a client-generated UUIDv4 — that is what makes a sync retry ' +
        'idempotent rather than duplicating the record',
    );
  }
  const updatedAt = record['updatedAt'];
  if (typeof updatedAt !== 'string' || Number.isNaN(Date.parse(updatedAt))) {
    throw new ValidationFailed('updatedAt must be an ISO-8601 timestamp');
  }

  const body = record['body'];
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw new ValidationFailed('body must be an object');
  }
  assertIntegerQuantities(body as Record<string, unknown>);

  return {
    entityType: record['entityType'],
    id,
    updatedAt,
    deleted: record['deleted'] === true,
    body: body as Record<string, unknown>,
  };
}

function assertIntegerQuantities(body: Record<string, unknown>): void {
  for (const field of INTEGER_FIELDS) {
    const value = body[field];
    if (value === undefined || value === null) continue;
    if (typeof value !== 'number' || !Number.isInteger(value)) {
      throw new ValidationFailed(
        `${field} must be an integer (centavos or grams). ` +
          'A fractional value means a client has introduced floating point, ' +
          'which breaks the guarantee that figures match the farmer’s calculator.',
      );
    }
  }
}
