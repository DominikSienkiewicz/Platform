# ADR-0003: Local platform resolution through an explicit platformRepository

## Status

Accepted — 2026-10-18

## Context

A consumer resolves the Platform settings plugin, convention plugins and catalog from GitHub
Packages. To try a Platform change that is not released yet, a developer needs the consumer
to resolve a locally published build instead, and several ad hoc routes have been used: an
implicit `mavenLocal()`, which silently mixes stale local artifacts into every build; releasing
a version just to test it, which spends an immutable version on an experiment; and editing the
consumer's repositories by hand.

The settings convention and the JVM templates already support one explicit route, and
Platform's own TestKit suite uses it: the build publishes to an isolated repository and passes
it to the consumer builds.

## Decision

`-PplatformRepository=<repository URI>` is the only official way to test an unreleased
Platform change on a consumer.

- When the property is set, `seniordev.settings-conventions` puts that repository first in
  `dependencyResolutionManagement`, and the consumer's `pluginManagement` puts it first for
  plugin resolution, as `templates/jvm/*/settings.gradle.kts` do. Without the property, nothing
  local is consulted.
- No convention or template declares `mavenLocal()`.
- A version is never released only to test it on a consumer.
- `buildAndPublishLocal.sh` publishes every Gradle module to the local Maven repository for this
  purpose; [docs/local-development.md](../local-development.md) describes the workflow.

## Consequences

- (+) Local resolution is visible on the command line and reproducible: the same build without
  the property resolves only published artifacts.
- (+) TestKit and developers exercise the same mechanism.
- (−) A consumer whose `pluginManagement` predates the templates ignores the property for
  plugins and must adopt the template wiring first.
- (−) A missing local artifact can still fall through to an authenticated remote lookup.

## Revisit when

- Platform moves off GitHub Packages, or consumers adopt composite builds for local work.
