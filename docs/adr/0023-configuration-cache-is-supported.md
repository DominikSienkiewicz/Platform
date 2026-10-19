# ADR-0023: The configuration cache is supported and gated in TestKit

## Status

Accepted — 2026-10-19

## Context

The configuration cache makes repeated builds fast, but a plugin that reads the project at execution time breaks
it, and consumers would find that only after enabling it.

## Decision

Every convention task is compatible with the configuration cache, and Platform's TestKit suite runs every consumer
build with `--configuration-cache` and fails on a deprecation the conventions cause (Decision 10). Consumers opt in
with `org.gradle.configuration-cache=true`.

## Consequences

- New convention code reads providers, not the project, at execution time.
- A plugin Platform applies that breaks the cache blocks its adoption until it is fixed.

## Revisit when

Gradle makes the configuration cache the default.
