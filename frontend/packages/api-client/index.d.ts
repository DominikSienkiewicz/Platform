export declare class ApiError extends Error {
  readonly name: "ApiError";
  readonly status: number;
  readonly body: unknown;
  constructor(status: number, message: string, body?: unknown);
}

export interface ApiClientOptions {
  /** Domyślnie z NEXT_PUBLIC_API_BASE_URL. */
  baseUrl?: string;
  headers?: Record<string, string>;
}

export interface ApiClient {
  request<T = unknown>(path: string, init?: RequestInit): Promise<T>;
  get<T = unknown>(path: string, init?: RequestInit): Promise<T>;
  post<T = unknown>(path: string, data?: unknown, init?: RequestInit): Promise<T>;
  put<T = unknown>(path: string, data?: unknown, init?: RequestInit): Promise<T>;
  patch<T = unknown>(path: string, data?: unknown, init?: RequestInit): Promise<T>;
  delete<T = unknown>(path: string, init?: RequestInit): Promise<T>;
}

export declare function createApiClient(options?: ApiClientOptions): ApiClient;
export declare const apiClient: ApiClient;
