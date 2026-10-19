# ADR-0026: Platform's own npm dependencies follow its frontend canon

## Status

Accepted — 2026-10-19

## Context

The frontend canon governs every consumer's dependencies, but Platform's own packages declared theirs freely, so
a package could ship with a version the canon did not allow.

## Decision

- Every package of the workspace pins its `dependencies` and `devDependencies` at the canon; `eslint-config` and
  `ui` pin their peers exactly, the others use ranges that admit the canon; `self-canon.test.mjs` guards it
  (Decision 20).
- `frontend-ci.yml` keeps `strict: false` as its default, and every snippet in the docs shows `strict: true`
  (Decision 21).

## Consequences

- A canon change reaches Platform's own packages in the same pull request.

## Revisit when

A MAJOR release: then `strict: true` becomes the default.
