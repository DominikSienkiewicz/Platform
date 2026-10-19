# API contracts: contract-first OpenAPI

> **Incubating.** No consumer has adopted the kit yet. Azimuth's `OpenApiPathCoverageTest` and
> `check-openapi-generated.mjs` are the patterns it generalises.

Every HTTP API between a backend and a frontend is described by one hand-written OpenAPI spec that is
committed to the repository. The spec is the contract: the backend is tested against it, the frontend
generates its types from it, and a pull request that breaks it needs an explicit label. Nothing
generates the spec from the code.

| Layer | What holds it to the spec | Fails when |
|---|---|---|
| Backend (Spring MVC) | `AbstractOpenApiContractTest` from `platform-test-fixtures` | a controller mapping is missing from the spec, or the spec describes an operation no controller implements |
| Frontend types | `platform-openapi-check` from `@dominiksienkiewicz/openapi`, run by strict `frontend-ci` | the committed `.d.ts` differs from what the committed spec generates |
| Frontend calls | `createApiClient<paths>()` from `@dominiksienkiewicz/api-client` | `tsc` finds a path the spec does not declare for that method, or a wrong request body |
| Pull requests | reusable `api-contract.yml` (oasdiff) | the change breaks existing clients and the pull request has no `api-breaking` label |

## Backend: the spec matches the controllers

Extend `AbstractOpenApiContractTest` in the backend's tests. It scans the `@RestController` classes of
`basePackage()` without starting Spring, so it needs no Docker. The snippet and everything it reports
are in [reference.md](reference.md#test-fixtures).

```java
class OpenApiContractTest extends AbstractOpenApiContractTest {
  @Override
  protected Path specPath() {
    return Path.of("../contract/openapi.yaml");
  }

  @Override
  protected String basePackage() {
    return "pl.seniordeveloper.myapp";
  }
}
```

The test covers Spring MVC only; a WebFlux controller is not scanned.

## Frontend: generated types

Add `@dominiksienkiewicz/openapi` and `openapi-typescript` to `devDependencies` at the canon versions,
and name the spec and the generated file in `package.json`:

```json
{
  "platform": {
    "openapi": { "spec": "../contract/openapi.yaml", "output": "src/api/schema.d.ts" }
  },
  "scripts": {
    "gen:api": "platform-openapi-gen",
    "gen:api:check": "platform-openapi-check"
  }
}
```

`platform-openapi-gen` writes the types; commit them. `platform-openapi-check` exits 1 when they are
missing or stale, and 2 when `platform.openapi` is not configured. Strict `frontend-ci` runs the check
for every repository that configures `platform.openapi` and fails when the package is not installed.

## Frontend: typed calls

`createApiClient` takes the generated `paths` interface as a type argument. Types only: the runtime is
the same client.

```ts
import { createApiClient } from "@dominiksienkiewicz/api-client";
import type { paths } from "@/api/schema";

export const api = createApiClient<paths>();

const pet = await api.get(`/pets/${id}`); // components["schemas"]["Pet"]
await api.post("/pets", { name: "Rex" }); // the body is checked against the operation
```

A path must fill in a template the spec declares for that method; a plain `string` does not type-check,
so build it with a template literal. The result is the union of the operation's 2xx JSON bodies, and
`null` for a response without content. `request()` stays untyped for a call the spec does not describe.
`@dominiksienkiewicz/api-client` is private until its first adopter
([api-client.md](api-client.md)).

## Errors: Problem Details

Errors have one shape across Platform: RFC 9457 `application/problem+json`, which
`platform-web-starter` writes ([reference](reference.md#web-starter-incubating)) and `api-client` reads
into `ApiError.problem`. [`contracts/problem-detail.json`](../contracts/problem-detail.json) is the golden
example: the starter's test compares a real 400 response with it, and the api-client test parses the same
file, so neither side can change the shape alone. Describe the errors in the committed spec with the
component in [`contracts/problem-detail.openapi.yaml`](../contracts/problem-detail.openapi.yaml): copy its
`components` and answer each error with `$ref: "#/components/responses/Problem"`.
`templates/tests/problem-detail-contract.test.sh` keeps the golden example inside that schema.

## Pull requests: breaking changes

`api-contract.yml` compares the spec at the pull request's base with the one in the pull request,
writes oasdiff's changelog to the job summary and fails on a change at or above `fail-on` (default
`ERR`). A pull request labelled `api-breaking` passes with a warning: say in its description why the
break is acceptable and how clients move. A spec that does not exist at the base yet passes. The caller
snippet is in [reusable-workflows.md](reusable-workflows.md#api-contractyml).
