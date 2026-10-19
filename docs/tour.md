# A reviewer's tour of Platform

Ten stops, each a problem a shared platform has to solve, the code that solves it here and the guard
that keeps it solved. Read it at a release tag (`https://github.com/DominikSienkiewicz/Platform/tree/vX.Y.Z/docs/tour.md`):
every link below is relative, so it then points at that release's code. The incidents behind several
stops are written up in [`notes/`](notes/); how the repository is built with coding agents is in
[engineering-with-agents.md](engineering-with-agents.md).

## 1. One pin, one catalog

Five product repositories consume Platform. Each pins one release in two places that move together:
the settings plugin and the version catalog. The settings plugin
([`seniordev.settings-conventions`](../gradle/build-logic/src/main/kotlin/seniordev.settings-conventions.settings.gradle.kts))
adds the repositories in a fixed order (an explicit `-PplatformRepository` first, then Maven Central, then
GitHub Packages) and refuses a Gradle older than the one TestKit proves. The catalog
([`libs.versions.toml`](../gradle/catalog/libs.versions.toml)) is the only place a library version is
written. Guard: `platform-doctor` (PD020) and the pin rewrite of `platform-bump` keep the two pins equal;
[versions.md](versions.md) explains why a catalog and not a BOM.

## 2. A gate against stray versions

`platformDependencyCheck` in
[`seniordev.java-conventions`](../gradle/build-logic/src/main/kotlin/seniordev.java-conventions.gradle.kts)
fails a consumer's `check` when a declared dependency or constraint carries a version the catalog does not
give, in every declarable bucket, Platform's own artifacts included, and its message names the `libs.…`
alias to use. Guard: the TestKit suite in
[`PlatformDependencyCheckFunctionalTest`](../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformDependencyCheckFunctionalTest.kt).

## 3. Versions the plugins impose come from the catalog

A precompiled script plugin cannot read a version catalog, so the toolchain, the quality tools and the
BOMs used to be literals mirrored next to the catalog. `generatePlatformVersions` in
[`build-logic/build.gradle.kts`](../gradle/build-logic/build.gradle.kts) now writes them into an internal
`PlatformVersions` object before the plugins compile. Guard:
[`PlatformVersionsTest`](../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformVersionsTest.kt)
fails on a version literal in a convention source. ADR: [0008](adr/0008-overrides-are-a-last-resort.md).

## 4. Consumers built by the tests

The convention plugins are tested the way they are used: Gradle TestKit builds copies of the
[`templates/jvm`](../templates/jvm/) starters against plugins and a catalog published to a local
repository, on the minimum supported Gradle and on Platform's own. Guard:
[`PlatformConsumerFunctionalTest`](../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformConsumerFunctionalTest.kt)
and [`PlatformMinimumGradleFunctionalTest`](../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformMinimumGradleFunctionalTest.kt);
CI also runs the reusable `backend-ci.yml` on the `java-library` starter.

## 5. A release that cannot be half published

[`release.sh`](../release.sh) tags only from a clean `main` equal to `origin/main`, with an English
Conventional Commit and a CHANGELOG section whose consumer actions decide between PATCH and MINOR.
[`release.yml`](../.github/workflows/release.yml) publishes only after CI passes on the tag, skips modules
whose version already exists instead of swallowing a conflict, attests every file, proves that every
artifact carries the version and that the release resolves as a consumer resolves it, and attaches a
credential-free bundle. Guard: the `templates/tests/release-*.test.sh` suite. The story behind it:
[notes/release-409.md](notes/release-409.md). ADR: [0002](adr/0002-release-and-versioning-contract.md).

## 6. Coverage counts every test that ran

`jacocoTestReport` reads only `test.exec` by default, so the integration tests of a Spring consumer ran and
were then thrown away. The convention sums `test` and `integrationTest`, and fails `check` when a threshold
is set but no test produced data. Guard: [`PlatformCoverageGateFunctionalTest`](../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformCoverageGateFunctionalTest.kt).
The story: [notes/integration-coverage.md](notes/integration-coverage.md).

## 7. Overrides above the Boot BOM are a last resort

When the newest Spring Boot manages a version Platform cannot ship (Lombok that fails on javac 27,
Tomcat and Jackson with fixed advisories, ArchUnit that cannot read Java 27 class files), the convention
overrides it in one place, with the condition for removing it. Guard: `canon-cve-scan.yml` every Monday and
[ADR-0008](adr/0008-overrides-are-a-last-resort.md). The ArchUnit case:
[notes/archunit-class-file-71.md](notes/archunit-class-file-71.md).

## 8. Integration that refuses to lose work

[`templates/merge.sh`](../templates/merge.sh) integrates a feature branch from its worktree and cleans up
only what a rebuild recreates: it refuses on uncommitted or irreplaceable ignored files, on a stale
`origin/main`, on a protected branch and on a second run in parallel, and deletes the branch only if its tip
did not move. [`worktree-new.sh`](../templates/worktree-new.sh) and
[`worktree-status.sh`](../templates/worktree-status.sh) cover the start of the same lifecycle. Guard:
[`merge.test.sh`](../templates/tests/merge.test.sh) and
[`worktree-lifecycle.test.sh`](../templates/tests/worktree-lifecycle.test.sh).

## 9. A machine shared by agents

Every layer of the stack sizes itself for a machine it owns. With `AI_AGENT=1`, the conventions give Java
tests one fork, a capped heap and at most four cached Spring contexts,
[`agent-gradle.sh`](../templates/agent-gradle.sh) limits workers and takes one of a few machine-wide test
slots across separate Gradle runs, and [`agent-preflight.sh`](../templates/agent-preflight.sh) says from
free memory and swap whether more agents may start. ADR: [0010](adr/0010-agent-resource-profile.md).

## 10. Roadmap to issues

[`templates/roadmap/`](../templates/roadmap/) turns a roadmap document into GitHub issues and a Projects
board, keeps them in sync through a marker contract, and moves an item to ready once its last prerequisite
closes (`roadmap-unblock.yml`). It is *experimental*: only the marker contract is stable (Decision 11).
Guard: the tests next to the scripts in [`templates/roadmap/scripts/lib`](../templates/roadmap/scripts/lib/),
which run them against a stubbed `gh`.
