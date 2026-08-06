// @dominiksienkiewicz/query — współdzielony QueryClient + provider.
// Zebrane z powielonego providera w Attestate (app/providers) i Pragmie (providers/QueryProvider):
// staleTime 60s, refetchOnWindowFocus off, Devtools poza produkcją, klient stabilny per-instancja.
//
// Bez JSX (czysty ESM, brak build-stepu) — używamy React.createElement.

import { createElement, useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ReactQueryDevtools } from "@tanstack/react-query-devtools";

/**
 * Fabryka QueryClient ze wspólnymi defaultami. Nadpisy przez `defaultOptions`.
 * @param {{ queries?: object, defaultOptions?: object }} [options]
 */
export function createQueryClient(options = {}) {
  return new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 60_000,
        refetchOnWindowFocus: false,
        ...options.queries,
      },
      ...options.defaultOptions,
    },
  });
}

/**
 * Provider React Query. Klient tworzony raz per instancja (useState) — bezpieczny w RSC/hydration.
 * @param {{ children: import("react").ReactNode, client?: import("@tanstack/react-query").QueryClient, devtools?: boolean }} props
 */
export function QueryProvider(props) {
  const { children, client } = props;
  const devtools =
    props.devtools ??
    (typeof process !== "undefined" && process.env && process.env.NODE_ENV !== "production");

  const [queryClient] = useState(() => client ?? createQueryClient());

  return createElement(
    QueryClientProvider,
    { client: queryClient },
    children,
    devtools ? createElement(ReactQueryDevtools, { initialIsOpen: false }) : null,
  );
}
