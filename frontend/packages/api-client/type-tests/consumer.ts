// Type test from a consumer's side, checked by `pnpm typecheck` and never run: the package is imported
// by name, so its exports resolve to index.d.ts as they do in a consumer.
import { ApiError, apiClient, createApiClient, type ApiClient, type ApiClientOptions } from "@dominiksienkiewicz/api-client";

export function consumerUse(): void {
  const options: ApiClientOptions = { baseUrl: "https://api.example.test", headers: { "X-Trace": "1" } };
  const client: ApiClient = createApiClient(options);

  const user: Promise<{ id: string }> = client.get<{ id: string }>("/users/1");
  const created: Promise<unknown> = client.post("/users", { name: "Ada" }, { cache: "no-store" });
  const removed: Promise<null> = apiClient.delete<null>("/users/1");
  void [user, created, removed];

  const error = new ApiError(404, "Not found", { message: "missing" });
  const failure: { status: number; body: unknown; name: "ApiError" } = error;
  const isError: Error = error;
  void [failure, isError];
}
