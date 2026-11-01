import { describe, expect, it, beforeEach } from 'vitest';
import { handleMutations } from '../../src/handlers/mutations.js';
import { handleSnapshot } from '../../src/handlers/snapshot.js';
import { handleReferenceData } from '../../src/handlers/reference.js';
import { MemoryStore } from '../../src/store/memory.js';
import type { AuthorizedEvent } from '../../src/auth/account.js';

/**
 * The routes in contracts/api.openapi.yaml, and the ordering and idempotency rules
 * in contracts/sync-protocol.md that OpenAPI cannot express.
 */
const SUB = '11111111-1111-4111-8111-111111111111';
const FIELD = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const CROPPING = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const EXPENSE = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

function event(overrides: Partial<AuthorizedEvent> = {}): AuthorizedEvent {
  return {
    requestContext: { authorizer: { jwt: { claims: { sub: SUB } } } },
    ...overrides,
  };
}

function mutation(seq: number, extra: Record<string, unknown> = {}) {
  return {
    seq,
    operation: 'upsert',
    entityType: 'field',
    id: FIELD,
    updatedAt: `2026-03-0${seq}T00:00:00.000Z`,
    body: { name: `Field v${seq}`, areaSqm: 25000 },
    ...extra,
  };
}

const body = (mutations: unknown[]) => JSON.stringify({ mutations });

describe('POST /v1/mutations', () => {
  let store: MemoryStore;
  beforeEach(() => (store = new MemoryStore()));

  it('applies a batch and reports the count', async () => {
    const response = await handleMutations(event({ body: body([mutation(1)]) }), store);
    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body).appliedCount).toBe(1);
  });

  it('is idempotent — a retried mutation does not duplicate the record', async () => {
    // sync-protocol.md I3: without this, a timeout that actually succeeded would
    // create a second expense and quietly overstate the farmer's season total.
    const payload = body([
      {
        seq: 1,
        operation: 'upsert',
        entityType: 'expense',
        id: EXPENSE,
        updatedAt: '2026-03-01T00:00:00.000Z',
        body: { croppingId: CROPPING, amountCentavos: 350000, category: 'labor' },
      },
    ]);
    await handleMutations(event({ body: payload }), store);
    await handleMutations(event({ body: payload }), store);
    await handleMutations(event({ body: payload }), store);

    expect(store.countFor(SUB)).toBe(1);
  });

  it('applies mutations in order so a correction wins', async () => {
    // FR-053e: out-of-order delivery would let a stale value overwrite a correction
    // in remote storage, leaving the durable copy wrong while the device shows the
    // right number.
    await handleMutations(
      event({ body: body([mutation(1), mutation(2), mutation(3)]) }),
      store,
    );
    const snapshot = await handleSnapshot(event(), store);
    expect(JSON.parse(snapshot.body).records[0].body.name).toBe('Field v3');
  });

  it('refuses a batch whose sequences are out of order', async () => {
    const response = await handleMutations(
      event({ body: body([mutation(3), mutation(1)]) }),
      store,
    );
    expect(response.statusCode).toBe(400);
    expect(JSON.parse(response.body).code).toBe('out_of_order');
  });

  it('stops at the first failure and reports its index', async () => {
    const response = await handleMutations(
      event({
        body: body([
          mutation(1),
          { ...mutation(2), id: 'not-a-uuid' },
          mutation(3),
        ]),
      }),
      store,
    );
    const parsed = JSON.parse(response.body);
    // 200 with failedIndex is deliberate: index 0 DID apply and must not be re-sent.
    expect(response.statusCode).toBe(200);
    expect(parsed.appliedCount).toBe(1);
    expect(parsed.failedIndex).toBe(1);
    expect(parsed.error.code).toBe('validation_failed');
  });

  it('rejects a fractional money amount', async () => {
    // A float here means a client has broken SC-009; it is refused rather than
    // stored where every later reader would inherit the drift.
    const response = await handleMutations(
      event({
        body: body([
          {
            seq: 1,
            operation: 'upsert',
            entityType: 'expense',
            id: EXPENSE,
            updatedAt: '2026-03-01T00:00:00.000Z',
            body: { croppingId: CROPPING, amountCentavos: 3500.5 },
          },
        ]),
      }),
      store,
    );
    expect(JSON.parse(response.body).failedIndex).toBe(0);
  });

  it('rejects an empty or oversized batch', async () => {
    expect((await handleMutations(event({ body: body([]) }), store)).statusCode).toBe(400);
    const oversized = Array.from({ length: 101 }, (_, i) => mutation(i + 1));
    expect(
      (await handleMutations(event({ body: body(oversized) }), store)).statusCode,
    ).toBe(413);
  });

  it('soft-deletes so the deletion propagates instead of being resurrected', async () => {
    // sync-protocol.md I4.
    await handleMutations(event({ body: body([mutation(1)]) }), store);
    await handleMutations(
      event({
        body: body([
          { seq: 2, operation: 'delete', entityType: 'field', id: FIELD,
            updatedAt: '2026-03-02T00:00:00.000Z' },
        ]),
      }),
      store,
    );

    const live = await handleSnapshot(event(), store);
    expect(JSON.parse(live.body).records).toHaveLength(0);

    // A catch-up sync still sees the tombstone, so the other device learns of it.
    const catchUp = await handleSnapshot(
      event({ queryStringParameters: { since: '2026-01-01T00:00:00.000Z' } }),
      store,
    );
    const records = JSON.parse(catchUp.body).records;
    expect(records).toHaveLength(1);
    expect(records[0].deleted).toBe(true);
  });
});

describe('GET /v1/snapshot', () => {
  it('returns the account’s records for a full restore', async () => {
    const store = new MemoryStore();
    await handleMutations(event({ body: body([mutation(1)]) }), store);
    const response = await handleSnapshot(event(), store);
    const parsed = JSON.parse(response.body);

    expect(response.statusCode).toBe(200);
    expect(parsed.records).toHaveLength(1);
    expect(parsed.hasMore).toBe(false);
    expect(parsed.serverTime).toBeTruthy();
  });
});

describe('GET /v1/reference-data', () => {
  it('needs no token, so a guest gets real recommendations (FR-026e)', async () => {
    const response = await handleReferenceData({});
    expect(response.statusCode).not.toBe(401);
  });

  it('answers a caller with no version with 204, never 304', async () => {
    // 304 is a statement about what the CALLER already holds: "the copy you have
    // is current". Said to someone who sent no `since`, it claims their nothing is
    // up to date. Caught against the deployed API on 2026-11-02, where a bare
    // GET returned 304 -- which the contract document does not allow.
    const response = await handleReferenceData({});
    expect(response.statusCode).toBe(204);
  });

  it('answers a caller who names a version with 304 when nothing is newer', async () => {
    const response = await handleReferenceData({
      queryStringParameters: { since: '1' },
    });
    expect(response.statusCode).toBe(304);
  });

  it('rejects a non-numeric since', async () => {
    const response = await handleReferenceData({
      queryStringParameters: { since: 'abc' },
    });
    expect(response.statusCode).toBe(400);
  });
});
