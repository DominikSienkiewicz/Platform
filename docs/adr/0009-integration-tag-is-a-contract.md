# ADR-0009: Test taxonomy — the `integration` JUnit tag is a public contract

## Status

Accepted — 2026-10-19

## Context

`seniordev.spring-modulith-conventions` splits a consumer's tests in two. The `test` task excludes
the JUnit tag `integration` and stays fast and Docker-free. The `integrationTest` task includes only
that tag; it runs the Testcontainers tests after `test`, and `check` runs both. `seniordev.java-conventions`
sums the coverage of both tasks, matching them by name, and the JaCoCo report deliberately does not
finalize `test`, so that `./gradlew test` never starts containers.

The tag name is a string in Platform's convention source and in the `@Tag("integration")`
annotations of the consumer repositories. Nothing documented it. A cleanup that renamed it in
Platform alone, to `it` or `slow` for example, would compile and pass in every repository, and
silently move every Testcontainers test into the fast `test` task, which then needs Docker and gets
slow, while `integrationTest` runs nothing.

## Decision

- The tag `integration` and the task names `test` and `integrationTest` are part of Platform's public
  contract, like a plugin ID or a property name (ADR-0007).
- A test that needs Docker, a network service or a Spring context backed by Testcontainers carries
  `@Tag("integration")`; every other test carries no tag and runs in `test`.
- A change of the tag or of either task name breaks every consumer. It ships only with an alias period
  in which both tags select `integrationTest`, and as a consumer action under the release contract
  (ADR-0002).
- `platform-test-fixtures` keeps its guard tests, such as `AbstractLiquibaseChangelogTest`,
  Docker-free and untagged, so that they run in `test`.

## Consequences

- A reviewer of a change to `useJUnitPlatform { excludeTags(...) }` or `includeTags(...)` knows it
  touches every consumer.
- Consumers can rely on `./gradlew test` never needing Docker, which is what the agent resource
  profile (ADR-0010) and local runs assume.
- A finer taxonomy, such as a separate tag for end-to-end tests, has to be added next to
  `integration`, not instead of it.
