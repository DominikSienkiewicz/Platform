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

Run whole suites only when asked; `lint` and `format` are the default gate. A failure carries a code such as
`[PLAT-DEP-001]`; its section in [gates.md](gates.md) names the fix.

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

## Claude Code skills

Platform ships a Claude Code plugin, `platform`, in the marketplace `seniordev-platform` at the root of this
repository (`.claude-plugin/marketplace.json`, `plugins/platform/`). Its skills hold no procedure: each tells the
agent to read the pinned Platform version (`platformVersion` in `backend/gradle.properties` or `gradle.properties`,
or the version in the `platform-agents` marker of `AGENTS.md`) and to open the runbook, or the section of the
failure's code in [gates.md](gates.md), at that tag. The runbooks stay the single source, and the guidance matches
the pin the same way the managed block's link to this sheet does.

| Skill | Use it when | Opens |
|---|---|---|
| `/platform:bump-consumer` | bumping the Platform pin | [bump a consumer](runbooks/bump-consumer.md) |
| `/platform:fix-gate-failure` | a build or CI run fails with a `[PLAT-…]` code | the section of the code in [gates.md](gates.md) |
| `/platform:add-library` | adding a JVM library or a frontend dependency | [add a JVM library](runbooks/add-jvm-library.md) or [add a frontend dependency](runbooks/add-frontend-dependency.md) |
| `/platform:test-unreleased-change` | previewing an unreleased Platform change on a consumer | [test an unreleased change](runbooks/test-unreleased-change.md) |
| `/platform:tdd-feature` | adding or changing behaviour test-first | [build a feature test-first](runbooks/tdd-feature.md) |
| `/platform:tdd-bugfix` | fixing a reported bug with a regression test first | [fix a bug test-first](runbooks/tdd-bugfix.md) |
| `/platform:ddd-modeling` | designing a domain, a bounded context or a module boundary | [model a domain with DDD](runbooks/ddd-modeling.md) |

Install it from a shell in the consumer repository. `#<ref>` pins the marketplace to a branch or tag: use the tag the
repository pins, or `#v1` for the latest 1.x release (the skills read the pin themselves, so both work). The
marketplace file exists from the first release that lists it in the [changelog](../CHANGELOG.md).

```bash
claude plugin marketplace add DominikSienkiewicz/Platform#v<version> --scope project
claude plugin install platform@seniordev-platform --scope project
```

`--scope project` records the marketplace in `.claude/settings.json`, which you commit; each collaborator then runs
the second command once. `platform-bump` does not touch that file, so an exact tag stays where it is until you move
it, while `#v1` follows the releases. A skill runs as `/platform:<skill>`, or Claude loads it from the situation its description
names: "bump platform", a red gate with a `PLAT-` code, a new dependency, a preview of an unreleased change, a
feature or a bug fix to write test-first, a domain to model. If the
page does not exist at the pinned tag, the pin predates it and the skill reads the same file on `main`.
`scripts/check-agent-docs.py` checks the commands, paths and tag links the skills name, like those of the other
agent documents.
