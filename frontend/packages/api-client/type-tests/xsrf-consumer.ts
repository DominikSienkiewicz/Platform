// Type test of the xsrf option from a consumer's side, checked by `pnpm typecheck` and never run.
import { createApiClient, type ApiClientOptions } from "@dominiksienkiewicz/api-client";

export function xsrfConsumer(): void {
  const springNames: ApiClientOptions = { xsrf: true };
  const customNames: ApiClientOptions = { xsrf: { cookie: "CSRF", header: "X-CSRF" } };
  const client = createApiClient({ baseUrl: "https://api.example.test", ...springNames });
  void [customNames, client];
}
