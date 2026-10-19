# ADR-0020: The versions the convention plugins impose come from the catalog

## Status

Accepted — 2026-10-19

## Context

A precompiled script plugin cannot read the version catalog at compile time, so the conventions held literal
copies of tool and BOM versions, guarded by mirror tests that compared them with the catalog.

## Decision

- `generatePlatformVersions` generates `PlatformVersions.kt` from the catalog; the convention plugins read its
  constants, and `PlatformVersionsTest` fails on a version literal in their sources (Decision 34).
- Mirrors outside Kotlin keep their tests: the `toolchain-java-version` defaults of the workflows and the Gradle
  wrappers.
- Catalog entries without a consumer go: the four "pragma" entries were removed, `openrewrite-bom` stays for
  Attestate (Decision 22).

## Consequences

- A version moves in one line of `libs.versions.toml`.
- The catalog lists only what a build resolves.

## Revisit when

Gradle lets precompiled script plugins read a catalog.
