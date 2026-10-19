# Platform rules for agents in consumer repositories

The rule sheet the `platform-agents` block of a consumer's `AGENTS.md` links at the pinned tag. It covers what an
agent needs to change a consumer without breaking a Platform gate; the procedures are in [runbooks](runbooks/).

## Versions

- JVM: declare every dependency through the catalog, `implementation(libs.jsoup)`. A dependency the Platform BOMs
  manage (Spring Boot starters, Jackson, JUnit) has no version at all. `./gradlew platformDependencyCheck` fails
  on an inline version, on a version that differs from the canon and on a `version(...)` override in
  `backend/settings.gradle.kts` ([gates](gates.md)).
- Frontend: every version in `frontend/package.json`, `overrides` included, is exact and equal to the canon of
  the installed `@dominiksienkiewicz/versions`; `npx platform-versions-check --fix` rewrites drift offline.
- A library the canon lacks is added in Platform first ([add a JVM library](runbooks/add-jvm-library.md),
  [add a frontend dependency](runbooks/add-frontend-dependency.md)), never inline in the consumer.
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

Run tests only when asked; `lint` and `format` are the default gate. A failure carries a code such as
`[PLAT-DEP-001]`; its section in [gates.md](gates.md) names the fix.

## Rules

- Reusable workflows are called at an exact `@vX.Y.Z`, which `scripts/platform-bump.sh` moves; never `@v1` and
  never `secrets: inherit`. Grant each workflow the permissions [reusable-workflows.md](reusable-workflows.md) lists.
- An unreleased Platform change is tested only through `-PplatformRepository`
  ([test an unreleased change](runbooks/test-unreleased-change.md)).
- Tag Testcontainers tests `integration` (`@IntegrationTest`, `@PostgresIntegrationTest`); `test` must not need
  Docker ([ADR-0009](adr/0009-integration-tag-is-a-contract.md)).
- Do not edit the files consumers copy from `templates/` by hand; `platform-templates-check` reports drift and the
  fix is a fresh copy.
- Do not edit inside the `platform-agents` markers of `AGENTS.md`: the next bump replaces it.
- Keep concepts, plans and analyses in the ignored `docs/concepts/`; add no AI attribution to commits or pull
  requests.

## Procedures

- [Bump a consumer](runbooks/bump-consumer.md)
- [Add a JVM library](runbooks/add-jvm-library.md)
- [Add a frontend dependency](runbooks/add-frontend-dependency.md)
- [Test an unreleased Platform change](runbooks/test-unreleased-change.md)
- [Promote an incubating artifact](runbooks/promote-incubating-artifact.md)
- [Cut a Platform release](runbooks/cut-release.md) (Platform maintainers)
