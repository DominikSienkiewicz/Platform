# Platform rules for agents in consumer repositories

The rule sheet the `platform-agents` block of a consumer's `AGENTS.md` links at the pinned tag. It covers what an
agent needs to change a consumer without breaking a Platform gate; the procedures are in [runbooks](runbooks/).

## Versions

- Platform owns the frame: Java, Gradle, the Spring BOMs, the libraries in `libs` and the frontend canon. Their
  versions are never overridden ([gates](gates.md)).
- JVM: declare a library of the frame through the catalog, `implementation(libs.jspecify)`. A dependency the Platform
  BOMs manage (Spring Boot starters, Jackson, JUnit) has no version at all. `./gradlew platformDependencyCheck` fails
  on an inline version of either, on a version that differs from the canon and on a `version(...)` override in
  `backend/settings.gradle.kts`.
- A library the frame does not know belongs to this repository: Gradle `appLibs` (`backend/gradle/app.versions.toml`,
  [consuming](consuming.md#libraries-your-application-owns)), frontend an exact version in `frontend/package.json`.
  Add it to Platform only when a second repository uses it ([add a JVM library](runbooks/add-jvm-library.md),
  [add a frontend dependency](runbooks/add-frontend-dependency.md)).
- Frontend: a package of the canon is exact and equal to the canon of the installed `@seniordeveloper-pl-dominik-sienkiewicz/versions`,
  `overrides` included; `npx platform-versions-check --fix` rewrites that drift offline and leaves your own packages
  alone.
- An override above a BOM or a transitive pin is a last resort with its removal condition
  ([ADR-0008](adr/0008-overrides-are-a-last-resort.md)); a CVE in a transitive npm package is fixed first with
  `npm update <package> --package-lock-only`.

## Commands

| Task | Command |
|---|---|
| Gradle in agent mode | `AI_AGENT=1 bash scripts/agent-gradle.sh <tasks>` ([agent profile](agent-profile.md)) |
| Formatter and linters, no tests | `./gradlew lint`, `./gradlew format` |
| Diagnose the setup | `frontend/node_modules/.bin/platform-doctor --gradle` |
| Bump Platform | `scripts/platform-bump.sh [X.Y.Z]`, with `--report` for the impact on this repository |
| Hand a branch off | `scripts/merge.sh <branch> '<conventional commit message>'` |

Run whole suites only when asked; `lint` and `format` are the default gate. A failure carries a code such as
`[PLAT-DEP-002]`; its section in [gates.md](gates.md) names the fix.

## Rules

- New behaviour and bug fixes are written test-first: the test comes before the code, and red and then green are
  observed by running only that test (`AI_AGENT=1 bash scripts/agent-gradle.sh test --tests <Class>`); red counts
  only as a failed assertion, never as a compile or setup error. A bug fix starts with a regression test that
  reproduces it and stays in the suite. One commit per behaviour keeps the branch green, and its body names the
  test that was red and why ([build a feature test-first](runbooks/tdd-feature.md),
  [fix a bug test-first](runbooks/tdd-bugfix.md)).
- Reusable workflows are called at an exact `@vX.Y.Z`, which `scripts/platform-bump.sh` moves; never `@v1` and
  never `secrets: inherit`. Grant each workflow the permissions [reusable-workflows.md](reusable-workflows.md) lists.
- An unreleased Platform change is tested only through `-PplatformRepository`
  ([test an unreleased change](runbooks/test-unreleased-change.md)).
- Tag Testcontainers tests `integration` (`@IntegrationTest`, `@PostgresIntegrationTest`); `test` must not need
  Docker ([ADR-0009](adr/0009-integration-tag-is-a-contract.md)).
- Do not edit the files consumers copy from `templates/` by hand; `platform-templates-check` reports drift and the
  fix is a fresh copy.
- Do not edit inside the Platform markers: `platform-agents` in `AGENTS.md`, `platform-agents-backend` in
  `backend/AGENTS.md` and `platform-agents-frontend` in `frontend/AGENTS.md`. They carry the rules and the stack
  of the pinned release, and the next bump replaces them. Write project rules outside the markers; a `CLAUDE.md`
  beside each file imports it with `@AGENTS.md`.
- Keep concepts, plans and analyses in the ignored `docs/concepts/`; add no AI attribution to commits or pull
  requests.

## Procedures

- [Bump a consumer](runbooks/bump-consumer.md)
- [Add a JVM library](runbooks/add-jvm-library.md)
- [Add a frontend dependency](runbooks/add-frontend-dependency.md)
- [Test an unreleased Platform change](runbooks/test-unreleased-change.md)
- [Promote an incubating artifact](runbooks/promote-incubating-artifact.md)
- [Build a feature test-first](runbooks/tdd-feature.md)
- [Fix a bug test-first](runbooks/tdd-bugfix.md)
- [Model a domain with DDD](runbooks/ddd-modeling.md)
- [Cut a Platform release](runbooks/cut-release.md) (Platform maintainers)
