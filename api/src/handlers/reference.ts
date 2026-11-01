import type { AuthorizedEvent } from '../auth/account.js';
import { bundleNewerThan, currentBundle } from '../reference/bundles.js';
import { json, type HandlerResponse } from './response.js';

/**
 * GET /v1/reference-data — the current agronomic bundle.
 *
 * UNAUTHENTICATED AND CACHEABLE BY DESIGN (research.md R10): this is public
 * agronomic guidance, identical for every farmer and containing nothing
 * account-specific. Keeping it off the authenticated path also means a guest
 * (FR-059) gets correct recommendations, which FR-026e requires.
 */
export async function handleReferenceData(
  event: AuthorizedEvent,
): Promise<HandlerResponse> {
  const raw = event.queryStringParameters?.['since'];
  const since = raw === undefined ? undefined : Number.parseInt(raw, 10);

  if (since !== undefined && Number.isNaN(since)) {
    return json(400, { code: 'validation_failed', message: 'since must be an integer' });
  }

  const bundle = since === undefined ? currentBundle() : bundleNewerThan(since);
  if (!bundle) {
    // 304 says "the copy you already have is current", so it is only honest to a
    // caller who told us what they have. A caller with no `since` has no copy, and
    // answering 304 would tell them their nothing was up to date. When this
    // deployment serves no bundle at all -- which is the state until feature 002
    // publishes one -- that caller gets 204: nothing here, and nothing wrong.
    const status = since === undefined ? 204 : 304;
    return { statusCode: status, headers: { 'cache-control': 'public, max-age=3600' }, body: '' };
  }

  return json(200, bundle, {
    // Bundles are immutable per version, so this can be cached hard.
    'cache-control': 'public, max-age=86400, immutable',
  });
}
