import { describe, expect, it, beforeEach } from 'vitest';
import { handleMutations } from '../../src/handlers/mutations.js';
import { handleSnapshot } from '../../src/handlers/snapshot.js';
import { handleDeleteAccount } from '../../src/handlers/account.js';
import { MemoryStore } from '../../src/store/memory.js';
import { deriveAccountId, Unauthorized } from '../../src/auth/account.js';
import type { AuthorizedEvent } from '../../src/auth/account.js';

/**
 * quickstart.md Scenario 8 — account isolation (FR-062).
 *
 * This is the one failure in the whole feature whose consequence is another
 * person's records rather than a wrong number, which is why it is an automated
 * contract test rather than a manual check.
 *
 * Account A must not be able to read or write account B's data by ANY means
 * available to a client: by id, by a crafted body field, by query parameter, or by
 * header. The account comes only from the verified token claim.
 */

const ALICE = '11111111-1111-4111-8111-111111111111';
const BOB = '22222222-2222-4222-8222-222222222222';

function tokenFor(sub: string): AuthorizedEvent['requestContext'] {
  return { authorizer: { jwt: { claims: { sub } } } };
}

function event(sub: string | null, overrides: Partial<AuthorizedEvent> = {}): AuthorizedEvent {
  return {
    ...(sub ? { requestContext: tokenFor(sub) } : {}),
    ...overrides,
  };
}

function upsert(id: string, name: string, seq = 1) {
  return JSON.stringify({
    mutations: [
      {
        seq,
        operation: 'upsert',
        entityType: 'field',
        id,
        updatedAt: '2026-03-01T00:00:00.000Z',
        body: { name, areaSqm: 25000 },
      },
    ],
  });
}

const ALICE_FIELD = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const BOB_FIELD = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

describe('account isolation (FR-062)', () => {
  let store: MemoryStore;

  beforeEach(async () => {
    store = new MemoryStore();
    await handleMutations(
      event(ALICE, { body: upsert(ALICE_FIELD, "Alice's field") }),
      store,
    );
    await handleMutations(
      event(BOB, { body: upsert(BOB_FIELD, "Bob's field") }),
      store,
    );
  });

  it('each farmer sees only their own records', async () => {
    const alice = await handleSnapshot(event(ALICE), store);
    const bob = await handleSnapshot(event(BOB), store);

    const aliceRecords = JSON.parse(alice.body).records;
    const bobRecords = JSON.parse(bob.body).records;

    expect(aliceRecords).toHaveLength(1);
    expect(aliceRecords[0].id).toBe(ALICE_FIELD);
    expect(JSON.stringify(aliceRecords)).not.toContain("Bob's field");

    expect(bobRecords).toHaveLength(1);
    expect(bobRecords[0].id).toBe(BOB_FIELD);
    expect(JSON.stringify(bobRecords)).not.toContain("Alice's field");
  });

  it('naming another account in the body is refused, not honoured', async () => {
    const response = await handleMutations(
      event(ALICE, {
        body: JSON.stringify({
          mutations: [
            {
              seq: 2,
              operation: 'upsert',
              entityType: 'field',
              id: BOB_FIELD,
              updatedAt: '2026-03-02T00:00:00.000Z',
              // The attack: claim to be writing into Bob's partition.
              body: { accountId: BOB, name: 'overwritten', areaSqm: 1 },
            },
          ],
        }),
      }),
      store,
    );

    expect(response.statusCode).toBe(400);
    expect(JSON.parse(response.body).code).toBe('validation_failed');

    // Bob's record is untouched.
    const bob = await handleSnapshot(event(BOB), store);
    expect(JSON.parse(bob.body).records[0].body.name).toBe("Bob's field");
  });

  it('naming another account by PK is refused', async () => {
    const response = await handleMutations(
      event(ALICE, {
        body: JSON.stringify({
          mutations: [
            {
              seq: 2,
              operation: 'upsert',
              entityType: 'field',
              id: BOB_FIELD,
              updatedAt: '2026-03-02T00:00:00.000Z',
              body: { PK: `ACCOUNT#${BOB}`, name: 'overwritten', areaSqm: 1 },
            },
          ],
        }),
      }),
      store,
    );
    expect(response.statusCode).toBe(400);
  });

  it('naming another account by query parameter is refused', async () => {
    const response = await handleSnapshot(
      event(ALICE, { queryStringParameters: { accountId: BOB } }),
      store,
    );
    expect(response.statusCode).toBe(400);
  });

  it('naming another account by header is refused', async () => {
    const response = await handleSnapshot(
      event(ALICE, { headers: { 'X-Account-Id': BOB } }),
      store,
    );
    expect(response.statusCode).toBe(400);
  });

  it('writing a record id that belongs to another farmer stays in the writer’s own partition', async () => {
    // Without naming an account, Alice writes using Bob's record id. Ids are
    // client-generated UUIDs so a collision is vanishingly unlikely, but if one
    // happened it must land in Alice's partition and leave Bob's alone.
    const response = await handleMutations(
      event(ALICE, { body: upsert(BOB_FIELD, 'Alice using Bob id', 2) }),
      store,
    );
    expect(response.statusCode).toBe(200);

    const bob = await handleSnapshot(event(BOB), store);
    expect(JSON.parse(bob.body).records[0].body.name).toBe("Bob's field");

    const alice = await handleSnapshot(event(ALICE), store);
    const names = JSON.parse(alice.body).records.map((r: any) => r.body.name);
    expect(names).toContain('Alice using Bob id');
  });

  it('a request with no token is rejected', async () => {
    const response = await handleSnapshot(event(null), store);
    expect(response.statusCode).toBe(401);
  });

  it('a token with an empty subject is rejected', async () => {
    const response = await handleSnapshot(
      { requestContext: { authorizer: { jwt: { claims: { sub: '' } } } } },
      store,
    );
    expect(response.statusCode).toBe(401);
  });

  it('deleting an account removes only that account’s records', async () => {
    await handleDeleteAccount(event(ALICE), store);

    expect(store.countFor(ALICE)).toBe(0);
    const bob = await handleSnapshot(event(BOB), store);
    expect(JSON.parse(bob.body).records).toHaveLength(1);
  });
});

describe('API Gateway flavour (REST v1 vs HTTP v2)', () => {
  // The two gateways put verified claims in different places and nothing warns you
  // when you read the wrong one — the claims are simply missing, so every request
  // looks unauthenticated and the API returns 401 for everybody. Moving Saka onto a
  // REST API to match the house Terraform pattern changed this shape, which is why
  // both are pinned here.
  it('reads the sub from a REST API (v1) cognito_user_pools authorizer', () => {
    const event = {
      requestContext: { authorizer: { claims: { sub: 'rest-user' } } },
    };
    expect(deriveAccountId(event)).toBe('rest-user');
  });

  it('reads the sub from an HTTP API (v2) JWT authorizer', () => {
    const event = {
      requestContext: { authorizer: { jwt: { claims: { sub: 'http-user' } } } },
    };
    expect(deriveAccountId(event)).toBe('http-user');
  });

  it('still refuses a request carrying no authorizer context at all', () => {
    // The claims come from requestContext.authorizer, which only API Gateway can
    // populate. A client that invents a body or header must not reach an account.
    expect(() => deriveAccountId({})).toThrow(Unauthorized);
    expect(() => deriveAccountId({ requestContext: {} })).toThrow(Unauthorized);
    expect(() => deriveAccountId({ requestContext: { authorizer: {} } })).toThrow(
      Unauthorized,
    );
  });
});
