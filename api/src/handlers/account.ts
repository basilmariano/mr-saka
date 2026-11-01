import { ClientSuppliedAccount, deriveAccountId, Unauthorized } from '../auth/account.js';
import type { AuthorizedEvent } from '../auth/account.js';
import type { Store } from '../store/types.js';
import { errorResponse, type HandlerResponse } from './response.js';

/**
 * DELETE /v1/account — delete the account and every record it owns.
 *
 * Not required by any FR, but a farmer who signs up must be able to leave with their
 * data actually gone.
 */
export async function handleDeleteAccount(
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

  await store.deleteAccount(accountId);
  return { statusCode: 204, headers: {}, body: '' };
}
