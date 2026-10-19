# API client

## Response contract

> **Incubating.** `@dominiksienkiewicz/api-client` is private and not published: no consumer has
> adopted it, and 1.5.31 is its last release in GitHub Packages. The contract below holds for that
> release and for the source, and becomes public again with its first adopter.

`@dominiksienkiewicz/api-client` returns parsed JSON for successful responses.
`createApiClient<paths>()` types the same client by the `paths` interface that `platform-openapi-gen`
generates from the committed spec ([api-contracts.md](api-contracts.md#frontend-typed-calls)).
A response with status 204 returns `null` without reading its body; other empty
responses also produce a `null` body. Invalid JSON in a successful response still
rejects with the original JSON parsing error.

Every request sends `Content-Type: application/json` unless a header replaces it. The client's
`headers` option replaces that default, and a call's `init.headers` replaces both, matched by name
without regard to case. `init.headers` accepts any `HeadersInit`: a plain object, a `Headers`
instance or an array of name and value pairs.

Without a `baseUrl` option the client prefixes every path with `NEXT_PUBLIC_API_BASE_URL`, or with
nothing when the variable is unset.

HTTP errors reject with `ApiError`, including HTML or plain-text responses from
an upstream service or proxy. The error retains the HTTP status. Its `body` is
parsed JSON when parsing succeeds, the original response text when parsing fails,
or `null` when empty. Its message uses the JSON body's `detail` (RFC 9457 Problem Details), then
its `message`, then its `title`, then the HTTP status text, then `HTTP <status>`. A response with
`Content-Type: application/problem+json` also sets `error.problem`, a `ProblemDetail` with `type`,
`title`, `status`, `detail`, `instance` and, when the server sends them, `errors` and `traceId`;
for any other response `problem` is `null`. Raw response text is retained for diagnostics and is not
used as the error message.

## Focused regression suites

Run the package tests from `frontend/` when test execution is requested:

```sh
pnpm --filter @dominiksienkiewicz/api-client test
pnpm --filter @dominiksienkiewicz/vitest-config test
```

The Vitest configuration tests import the public configuration and therefore
require its declared peer dependencies to be installed. They check the agent worker
budget ([agent-profile.md](agent-profile.md)) without executing Vitest suites.
