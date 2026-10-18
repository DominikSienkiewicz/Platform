# HTTP response handling and agent worker budget

## API client response contract

> **Incubating.** `@dominiksienkiewicz/api-client` is private and not published: no consumer has
> adopted it, and 1.5.31 is its last release in GitHub Packages. The contract below holds for that
> release and for the source, and becomes public again with its first adopter.

`@dominiksienkiewicz/api-client` returns parsed JSON for successful responses.
A response with status 204 returns `null` without reading its body; other empty
responses also produce a `null` body. Invalid JSON in a successful response still
rejects with the original JSON parsing error.

HTTP errors reject with `ApiError`, including HTML or plain-text responses from
an upstream service or proxy. The error retains the HTTP status. Its `body` is
parsed JSON when parsing succeeds, the original response text when parsing fails,
or `null` when empty. Its message uses the JSON body's `message` when available,
then the HTTP status text, then `HTTP <status>`. Raw response text is retained for
diagnostics and is not used as the error message.

## Vitest worker budget

`@dominiksienkiewicz/vitest-config` sets `test.maxWorkers` to 2 when the agent
harness sets `AI_AGENT=1` or `AI_AGENT=true`. The value is read when the configuration
module loads. Other values, including an absent variable, leave Vitest's default
worker count unchanged. `CI` alone does not enable the agent budget.

Consumers use the shared `baseConfig` as before. A consumer's explicit
`test.maxWorkers` override still takes precedence when merged after `baseConfig`.

## Focused regression suites

Run the package tests from `frontend/` when test execution is requested:

```sh
pnpm --filter @dominiksienkiewicz/api-client test
pnpm --filter @dominiksienkiewicz/vitest-config test
```

The Vitest configuration tests import the public configuration and therefore
require its declared peer dependencies to be installed. They check both agent
values, disabled values, and ordinary CI behavior without executing Vitest suites.
