# ADR-0037: Platform governs the frame, and consumers own the rest

## Status

Accepted — 2026-11-19. Partly supersedes [ADR-0001](0001-platform-single-source-and-latest-version-rule.md).

## Context

[ADR-0001](0001-platform-single-source-and-latest-version-rule.md) says that a new library means a catalog entry and a
release first, and only then a bump downstream. `platformDependencyCheck` ([PLAT-DEP-001](../gates.md#retired-codes))
and `platform-versions-check` (PLAT-FE-001) enforced it: an explicit version of a library outside the canon failed
the build. So a small change in an application, such as one more library used by that application alone, needed a
Platform release and a bump before the application could build.

That cost bought nothing for a library only one repository uses. The drift that ADR-0001 fights, the same library at
different versions across repositories, cannot happen with a library that has a single user.

## Decision

- Platform sets the versions of the frame and forbids overriding them. The frame is Java, Gradle, the Spring BOMs,
  the libraries in `libs` and the frontend canon. The gates that hold it stay: PLAT-DEP-002 (a version that differs
  from the canon), PLAT-DEP-003 (an explicit version of a library a BOM manages), PLAT-DEP-004 (a `version(...)`
  override of a canon module in `settings.gradle.kts`) and PLAT-FE-002 (a frontend version that differs from the
  canon).
- A library outside the frame belongs to the application. In Gradle it is registered in a second catalog,
  `appLibs`, read from `gradle/app.versions.toml`; in the frontend it is an exact version in `package.json`. A
  library that a Spring or Platform BOM manages takes no version in either place.
- A library moves into the frame when two or more repositories use it. The move is a catalog or canon entry and a
  release, as ADR-0001 describes, and from then on the gates hold its version.
- The frontend canon holds only the frame. A consumer's own packages and its `overrides` for them are its own, and
  neither `platform-versions-check` nor `platform-bump` rewrites them.

## Consequences

- PLAT-DEP-001 and PLAT-FE-001 are retired and never return ([ADR-0027](0027-gate-codes-are-a-contract.md)). A library or package
  without an entry in the canon no longer fails a build.
- An `appLibs` entry that collides with a canon module still fails PLAT-DEP-002, so a consumer cannot use the second
  catalog to move a framed version.
- Overrides of a frontend package outside the canon are owned by the consumer. `platform-bump` keeps them, so the
  migration `every-drop-stale-overrides` is removed, and `canon-diff` reports the removal of a frontend canon entry
  as "the consumer owns its version from now on", not as a consumer action. A Gradle catalog removal keeps its
  action, because the alias disappears from `libs`.
- ADR-0001 holds for everything in the frame. Only its sentence that a new library starts with a catalog entry and a
  release no longer holds as a rule for every library.
- The cost is that applications can drift on libraries outside the frame. That is accepted: such a library has one
  user, and the move into the frame at two users removes the drift.

## Revisit when

Two consumers use the same library without it being in the frame for long, or an application's own library
repeatedly causes a CVE that Platform has to chase.
