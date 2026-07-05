import type { ReactNode } from "react";
import type { QueryClient } from "@tanstack/react-query";

export interface CreateQueryClientOptions {
  /** Nadpisy defaultów `queries` (merge nad staleTime/refetchOnWindowFocus). */
  queries?: Record<string, unknown>;
  /** Nadpisy całego `defaultOptions`. */
  defaultOptions?: Record<string, unknown>;
}

export declare function createQueryClient(options?: CreateQueryClientOptions): QueryClient;

export interface QueryProviderProps {
  children: ReactNode;
  /** Własny klient; domyślnie tworzony przez createQueryClient(). */
  client?: QueryClient;
  /** Devtools; domyślnie włączone poza produkcją. */
  devtools?: boolean;
}

export declare function QueryProvider(props: QueryProviderProps): ReactNode;
