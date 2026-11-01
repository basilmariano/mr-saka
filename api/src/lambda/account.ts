import { handleDeleteAccount } from '../handlers/account.js';
import { DynamoStore } from '../store/dynamo.js';
import type { AuthorizedEvent } from '../auth/account.js';

const store = new DynamoStore(process.env['TABLE_NAME']!);
export const handler = (event: AuthorizedEvent) => handleDeleteAccount(event, store);
