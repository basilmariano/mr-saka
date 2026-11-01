export interface HandlerResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

export function json(statusCode: number, payload: unknown, headers: Record<string, string> = {}): HandlerResponse {
  return {
    statusCode,
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(payload),
  };
}

export function errorResponse(statusCode: number, code: string, message: string): HandlerResponse {
  // Messages are safe to show the farmer and never leak another account's data.
  return json(statusCode, { code, message });
}
