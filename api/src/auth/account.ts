/**
 * Deriving which account a request belongs to.
 *
 * THE INVARIANT (FR-062, contracts/sync-protocol.md I5):
 * the owning account comes EXCLUSIVELY from the verified Cognito JWT `sub` claim.
 * No request body field, query parameter, path parameter, or header may influence
 * it. A request that names an account id is rejected, not honoured.
 *
 * This is the one rule in the feature whose violation exposes another person's
 * records rather than producing a wrong number, which is why the account id is
 * derived in exactly one place and every caller must go through it.
 */

export class Unauthorized extends Error {
  readonly code = 'unauthorized';
  constructor(message = 'Missing or invalid token') {
    super(message);
  }
}

export class ClientSuppliedAccount extends Error {
  readonly code = 'validation_failed';
  constructor(readonly field: string) {
    super(
      `Request attempted to name an account via "${field}". ` +
        'The account is taken from the verified token only.',
    );
  }
}

/**
 * The shape API Gateway hands a Lambda after it has validated the JWT.
 *
 * The two API Gateway flavours put the verified claims in different places, and
 * nothing warns you when you read the wrong one — the claims are simply absent, so
 * every request looks unauthenticated:
 *
 *   REST API (v1), Cognito user pools authorizer -> requestContext.authorizer.claims
 *   HTTP API (v2), JWT authorizer                -> requestContext.authorizer.jwt.claims
 *
 * Both are accepted so the handler is not coupled to which one fronts it. What is
 * NOT negotiable is that the claims come from `requestContext.authorizer`, which
 * only API Gateway can populate — a client cannot forge it.
 */
export interface AuthorizedEvent {
  requestContext?: {
    authorizer?: {
      claims?: Record<string, unknown>;
      jwt?: { claims?: Record<string, unknown> };
    };
  };
  headers?: Record<string, string | undefined>;
  queryStringParameters?: Record<string, string | undefined> | null;
  body?: string | null;
}

/** Fields a malicious or buggy client might use to try to address another account. */
const FORBIDDEN_FIELDS = ['accountId', 'account_id', 'PK', 'pk', 'sub', 'ownerId'];

/**
 * Returns the Cognito `sub` for this request.
 *
 * @throws Unauthorized when the token is absent or carries no usable subject.
 * @throws ClientSuppliedAccount when the request tries to name an account itself.
 */
export function deriveAccountId(event: AuthorizedEvent): string {
  rejectClientSuppliedAccount(event);

  const authorizer = event.requestContext?.authorizer;
  const claims = authorizer?.jwt?.claims ?? authorizer?.claims;
  const sub = claims?.['sub'];
  if (typeof sub !== 'string' || sub.length === 0) {
    throw new Unauthorized();
  }
  return sub;
}

/**
 * Refuses the request outright if it tries to name an account.
 *
 * Silently ignoring such a field would also be safe, but refusing makes a client
 * bug loud instead of letting it look like it worked.
 */
export function rejectClientSuppliedAccount(event: AuthorizedEvent): void {
  const query = event.queryStringParameters ?? {};
  for (const field of FORBIDDEN_FIELDS) {
    if (query[field] !== undefined) throw new ClientSuppliedAccount(field);
  }

  const headers = event.headers ?? {};
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === 'x-account-id') {
      throw new ClientSuppliedAccount(key);
    }
  }

  if (!event.body) return;
  let parsed: unknown;
  try {
    parsed = JSON.parse(event.body);
  } catch {
    return; // malformed bodies are the handler's problem, not this one's
  }
  assertNoAccountField(parsed);
}

function assertNoAccountField(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) assertNoAccountField(item);
    return;
  }
  if (value === null || typeof value !== 'object') return;

  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    if (FORBIDDEN_FIELDS.includes(key)) throw new ClientSuppliedAccount(key);
    assertNoAccountField(nested);
  }
}
