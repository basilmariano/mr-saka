import { handleReferenceData } from '../handlers/reference.js';
import type { AuthorizedEvent } from '../auth/account.js';

export const handler = (event: AuthorizedEvent) => handleReferenceData(event);
