# ADR-0011: Contract-first OpenAPI: the committed spec is the contract

## Status

Accepted — 2026-10-19

## Context

Every HTTP API between a backend and a frontend must be described with OpenAPI, and consumers generate
their client types from it. Two consumers had built this independently, both from a hand-written spec
committed to the repository: Azimuth tested its controllers against `contract/openapi.json` and checked
its generated frontend types in `typecheck`, and Touchstone kept `api/openapi.yml` as its "shared HTTP
contract" with no generator yet. Nothing in Platform supported the rule, and nothing noticed a pull
request that broke the contract for existing clients.

Two sources of truth were possible: generate the spec from the code (springdoc), or write the spec by
hand and hold the code to it.

## Decision

The hand-written spec committed to the repository is the contract (contract-first), and Platform holds
every layer to it:

- the backend with `AbstractOpenApiContractTest` from `platform-test-fixtures`, which compares the spec
  with the Spring MVC mappings in both directions without Docker;
- the frontend types with `platform-openapi-gen` and `platform-openapi-check` from
  `@dominiksienkiewicz/openapi`, which strict `frontend-ci` runs for every repository that configures
  `platform.openapi`;
- the frontend calls with `createApiClient<paths>()` from `@dominiksienkiewicz/api-client`, typed by the
  generated `paths`;
- pull requests with the reusable `api-contract.yml`, which runs oasdiff against the base and fails on a
  breaking change unless the pull request carries the `api-breaking` label.

[docs/api-contracts.md](../api-contracts.md) describes the flow.

## Consequences

- The spec is reviewed like code: a change to an endpoint is a change to the spec first, and the drift
  test, the generated types and the breaking-change gate all point at the same file.
- springdoc is not part of the platform. A consumer that generates its spec from code does not get the
  drift test's guarantee, because there is nothing independent to compare against.
- The drift test reads Spring MVC mappings only; WebFlux controllers are not covered.
- The `api-breaking` label can turn into a rubber stamp; the gate asks for the reason in the pull
  request description.

## Revisit when

A consumer needs WebFlux, or the portfolio moves to generating the spec from code.
