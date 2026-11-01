import { ClientSuppliedAccount, deriveAccountId, Unauthorized } from '../auth/account.js';
import type { AuthorizedEvent } from '../auth/account.js';
import type { Store } from '../store/types.js';
import { ValidationFailed, validateRecord } from '../validation/record.js';
import { errorResponse, json, type HandlerResponse } from './response.js';

const MAX_BATCH = 100;

interface Mutation {
  seq: number;
  operation: 'upsert' | 'delete';
  entityType: string;
  id: string;
  updatedAt?: string;
  body?: Record<string, unknown>;
}

/**
 * POST /v1/mutations — apply an ordered batch from the device outbox.
 *
 * ORDER MATTERS (FR-053e, sync-protocol.md I2): mutations are applied in array
 * order. If one fails, everything before it has already been applied, so the
 * response reports `failedIndex` and the device resumes from there rather than
 * re-sending what already landed or skipping ahead past the failure.
 *
 * IDEMPOTENT (sync-protocol.md I3): every record carries a client-generated UUID, so
 * an upsert is a put on a known key. A retry after an ambiguous timeout overwrites an
 * identical record instead of creating a second expense and overstating the farmer's
 * season total.
 */
export async function handleMutations(
  event: AuthorizedEvent,
  store: Store,
): Promise<HandlerResponse> {
  let accountId: string;
  try {
    accountId = deriveAccountId(event);
  } catch (error) {
    if (error instanceof ClientSuppliedAccount) {
      return errorResponse(400, error.code, error.message);
    }
    if (error instanceof Unauthorized) {
      return errorResponse(401, error.code, error.message);
    }
    throw error;
  }

  let mutations: Mutation[];
  try {
    const parsed = JSON.parse(event.body ?? '') as { mutations?: unknown };
    if (!Array.isArray(parsed.mutations) || parsed.mutations.length === 0) {
      return errorResponse(400, 'malformed_batch', 'mutations must be a non-empty array');
    }
    mutations = parsed.mutations as Mutation[];
  } catch {
    return errorResponse(400, 'malformed_batch', 'Body must be JSON');
  }

  if (mutations.length > MAX_BATCH) {
    return errorResponse(413, 'malformed_batch', `At most ${MAX_BATCH} mutations per batch`);
  }

  // FR-053e: a batch whose sequences are out of order would silently reorder the
  // farmer's corrections, so it is refused rather than guessed at.
  for (let i = 1; i < mutations.length; i++) {
    if (!(mutations[i]!.seq > mutations[i - 1]!.seq)) {
      return errorResponse(
        400,
        'out_of_order',
        'mutations must be strictly increasing by seq',
      );
    }
  }

  let applied = 0;
  for (let index = 0; index < mutations.length; index++) {
    const mutation = mutations[index]!;
    try {
      if (mutation.operation === 'delete') {
        await store.softDelete(
          accountId,
          validateRecord({
            entityType: mutation.entityType,
            id: mutation.id,
            updatedAt: mutation.updatedAt ?? new Date().toISOString(),
            deleted: true,
            body: mutation.body ?? {},
          }).entityType,
          mutation.id,
          mutation.body?.['croppingId'] as string | undefined,
          mutation.updatedAt ?? new Date().toISOString(),
        );
      } else {
        const record = validateRecord({
          entityType: mutation.entityType,
          id: mutation.id,
          updatedAt: mutation.updatedAt,
          deleted: false,
          body: mutation.body,
        });
        await store.put(accountId, record);
      }
      applied++;
    } catch (error) {
      const message = error instanceof ValidationFailed ? error.message : 'Internal error';
      const code = error instanceof ValidationFailed ? error.code : 'internal';
      // 200 with failedIndex is deliberate: everything before the failure DID
      // apply, and the device must not re-send it.
      return json(200, {
        appliedCount: applied,
        failedIndex: index,
        error: { code, message },
        serverTime: new Date().toISOString(),
      });
    }
  }

  return json(200, { appliedCount: applied, serverTime: new Date().toISOString() });
}
