import { ClientSuppliedAccount, deriveAccountId, Unauthorized } from '../auth/account.js';
import type { AuthorizedEvent } from '../auth/account.js';
import type { Store } from '../store/types.js';
import { errorResponse, json, type HandlerResponse } from './response.js';

/**
 * GET /v1/snapshot — the signed-in farmer's complete history.
 *
 * FR-052, FR-064: this is what restores a farmer onto a replacement phone with
 * nothing re-entered. SC-013 requires 100% recovery with no figure differing.
 */
export async function handleSnapshot(
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

  const query = event.queryStringParameters ?? {};
  const page = await store.snapshot(accountId, {
    ...(query['cursor'] ? { cursor: query['cursor'] } : {}),
    ...(query['since'] ? { since: query['since'] } : {}),
  });

  return json(200, {
    records: page.records,
    ...(page.nextCursor ? { nextCursor: page.nextCursor } : {}),
    hasMore: page.hasMore,
    serverTime: new Date().toISOString(),
  });
}
