// Type test from a consumer's side, checked by `pnpm typecheck` and never run: the package is imported
// by name, so its exports resolve to index.d.ts as they do in a consumer.
import type { QueryClient } from "@tanstack/react-query";
import type { ReactNode } from "react";
import {
  createQueryClient,
  QueryProvider,
  type CreateQueryClientOptions,
  type QueryProviderProps,
} from "@dominiksienkiewicz/query";

export function consumerUse(): void {
  const options: CreateQueryClientOptions = { queries: { staleTime: 0 }, defaultOptions: { mutations: { retry: 1 } } };
  const client: QueryClient = createQueryClient(options);
  const defaults: QueryClient = createQueryClient();

  const props: QueryProviderProps = { children: null, client, devtools: false };
  const tree: ReactNode = QueryProvider(props);
  void [defaults, tree];
}
