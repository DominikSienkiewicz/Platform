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

type HttpMethod = "get" | "post" | "put" | "patch" | "delete";
type SuccessStatus = 200 | 201 | 202 | 203 | 204 | 205 | 206 | "2XX";

/** `"/pets/{id}"` → `` `/pets/${string}` ``: the shape of a path template once its parameters are filled in. */
export type FilledPath<Template extends string> = Template extends `${infer Head}{${string}}${infer Tail}`
  ? `${Head}${string}${FilledPath<Tail>}`
  : Template;

type PathsWith<Paths, Method extends HttpMethod> = {
  [Template in keyof Paths & string]: Paths[Template] extends { [M in Method]: infer Operation }
    ? [Operation] extends [never]
      ? never
      : Template
    : never;
}[keyof Paths & string];

type MatchingTemplate<Paths, Method extends HttpMethod, Path extends string> = {
  [Template in PathsWith<Paths, Method>]: Path extends FilledPath<Template> ? Template : never;
}[PathsWith<Paths, Method>];

type CheckedPath<Paths, Method extends HttpMethod, Path extends string> = [
  MatchingTemplate<Paths, Method, Path>,
] extends [never]
  ? FilledPath<PathsWith<Paths, Method>>
  : Path;

type OperationIn<Item, Method extends HttpMethod> = Item extends { [M in Method]: infer Operation } ? Operation : never;
type OperationOf<Paths, Method extends HttpMethod, Path extends string> = OperationIn<
  Paths[MatchingTemplate<Paths, Method, Path>],
  Method
>;

type OrUnknown<T> = [T] extends [never] ? unknown : T;
type ContentOf<Response> = Response extends { content: infer Content } ? Content[keyof Content] : null;
type ResponseOf<Operation> = Operation extends { responses: infer Responses }
  ? OrUnknown<{ [Status in keyof Responses & SuccessStatus]: ContentOf<Responses[Status]> }[keyof Responses & SuccessStatus]>
  : unknown;

type BodyOf<Operation> = Operation extends { requestBody?: never }
  ? undefined
  : Operation extends { requestBody: { content: infer Content } }
    ? Content[keyof Content]
    : Operation extends { requestBody?: { content: infer Content } }
      ? Content[keyof Content] | undefined
      : unknown;
type BodyArgs<Operation> = undefined extends BodyOf<Operation>
  ? [data?: BodyOf<Operation>, init?: RequestInit]
  : [data: BodyOf<Operation>, init?: RequestInit];

/**
 * {@link ApiClient} typed by the `paths` interface that openapi-typescript generates from the committed spec
 * (`platform-openapi-gen`): a path must fill in a template the spec declares for that method, the request body is
 * the operation's JSON body and the result is the union of its 2xx bodies (`null` for a response without content).
 * Types only — the runtime is the same client.
 */
export interface TypedApiClient<Paths> {
  get<Path extends string>(
    path: CheckedPath<Paths, "get", Path>,
    init?: RequestInit,
  ): Promise<ResponseOf<OperationOf<Paths, "get", Path>>>;
  delete<Path extends string>(
    path: CheckedPath<Paths, "delete", Path>,
    init?: RequestInit,
  ): Promise<ResponseOf<OperationOf<Paths, "delete", Path>>>;
  post<Path extends string>(
    path: CheckedPath<Paths, "post", Path>,
    ...args: BodyArgs<OperationOf<Paths, "post", Path>>
  ): Promise<ResponseOf<OperationOf<Paths, "post", Path>>>;
  put<Path extends string>(
    path: CheckedPath<Paths, "put", Path>,
    ...args: BodyArgs<OperationOf<Paths, "put", Path>>
  ): Promise<ResponseOf<OperationOf<Paths, "put", Path>>>;
  patch<Path extends string>(
    path: CheckedPath<Paths, "patch", Path>,
    ...args: BodyArgs<OperationOf<Paths, "patch", Path>>
  ): Promise<ResponseOf<OperationOf<Paths, "patch", Path>>>;
  /** Untyped escape hatch for a call the spec does not describe. */
  request<T = unknown>(path: string, init?: RequestInit): Promise<T>;
}

export declare function createApiClient(options?: ApiClientOptions): ApiClient;
export declare function createApiClient<Paths>(options?: ApiClientOptions): TypedApiClient<Paths>;
export declare const apiClient: ApiClient;
