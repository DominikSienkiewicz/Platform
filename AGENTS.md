# AGENTS.md — Platform

Tool-neutral guidance for coding agents working **in this repository**. Platform is the shared build,
quality, version and frontend layer of the consumer repositories in `scripts/consumers.txt`; it publishes
versioned artifacts to GitHub Packages, and consumers pin one release. `CLAUDE.md` holds the same rules in
Polish with the maintainer's detail; the block at the end is what `platform-bump` writes into every
consumer's `AGENTS.md`.

## Layout

| Path | What it is |
|---|---|
| `gradle/build-logic/` | the convention plugins `seniordev.{java,quality,spring-modulith,sonar,nullness}-conventions` and the settings plugin `seniordev.settings-conventions` |
| `gradle/catalog/` | the published version catalog `pl.seniordeveloper:platform-catalog`, the single source of JVM versions |
| `gradle/bom/` | `pl.seniordeveloper:platform-bom`: the Spring BOM imports, CVE floors and compatibility overrides |
| `gradle/test-fixtures/`, `gradle/*-starter/` | the test fixtures and the incubating Spring Boot starters |
| `frontend/packages/` | the npm packages; `versions/versions.json` is the single source of frontend versions |
| `.github/workflows/` | the reusable workflows consumers call, and Platform's own CI and release |
| `templates/` | files consumers copy byte for byte, with their tests in `templates/tests/` |
| `docs/` | maintained documentation; `docs/adr/` holds the decisions, `docs/runbooks/` the procedures |

## Hard rules

1. Every JVM library or plugin version lives in `gradle/catalog/libs.versions.toml`; the convention plugins
   read it through the generated `PlatformVersions`. A literal version in a convention plugin fails
   `PlatformVersionsTest`.
2. Every frontend dependency version lives in `frontend/packages/versions/versions.json`, exact, overrides
   included; `platform-versions-check` enforces it in consumers and `self-canon.test.mjs` in Platform.
3. A convention plugin adds no business dependency (security, jOOQ, AI models); consumers declare those.
4. `seniordev.spring-modulith-conventions` does not apply the Spring Boot plugin.
5. SpotBugs stays report-only until both criteria of `docs/adr/0005-spotbugs-report-only.md` hold.
6. Sonar lives in `seniordev.quality-conventions` and runs from the root project only.
7. Overrides above a BOM are a last resort, each with its removal condition (`docs/adr/0008-overrides-are-a-last-resort.md`).
8. After changing what a Platform module resolves, run `scripts/write-verification-metadata.sh`.
9. Language: Polish only in `CLAUDE.md` and in code and workflow comments; everything else in English.

## Working here

- Gate: `./gradlew lint` and `./gradlew format` in the module you touched, `shellcheck` and `actionlint`
  for scripts and workflows; tests only when asked. A gate failure names its code (`docs/gates.md`).
- Every bug fix starts with a regression test; an existing test changes only with the owner's approval.
- Releases: `./release.sh "<conventional commit>" [X.Y.Z]` on `main`, after `scripts/canary.sh`; see
  `RELEASING.md` and `docs/runbooks/cut-release.md`.
- Work in a worktree under `.worktrees/` on `<type>/<description>-YYYY-MM-DD`; the owner integrates with
  `./merge.sh <branch> "<conventional commit message>"`.
- New concepts, plans and analyses go to the ignored `docs/concepts/`.

## The block consumers get

`platform-bump` writes the block below into the `AGENTS.md` of every consumer, with `{{VERSION}}` filled in as the
release it bumps to (`frontend/packages/versions/bin/sync-agents-block.py`). Its source is
`templates/agents/platform-block.md`; this copy must stay identical, which `templates/tests/agent-docs.test.sh` checks.

<!-- BEGIN platform-agents v{{VERSION}} (managed by platform-bump; edits inside these markers are replaced) -->
## Platform rules for agents (Platform {{VERSION}})

For a repository that pins [DominikSienkiewicz/Platform](https://github.com/DominikSienkiewicz/Platform) {{VERSION}}.
The full rule sheet of that release: https://github.com/DominikSienkiewicz/Platform/blob/v{{VERSION}}/docs/consumer-agents.md

- Versions come only from the catalog (`libs.<alias>` in Gradle) or the frontend canon (`versions.json`).
  Never write a version inline: `platformDependencyCheck` and `platform-versions-check` fail the build.
- A new library starts in Platform: an entry in `gradle/catalog/libs.versions.toml` or
  `frontend/packages/versions/versions.json`, a release, then `scripts/platform-bump.sh`, then `libs.<alias>`.
- Gate failures carry a code such as `[PLAT-DEP-001]` with a link; follow the fix it names.
- Run Gradle through `AI_AGENT=1 bash scripts/agent-gradle.sh <tasks>`. The default gate is `lint` and `format`;
  run tests only when asked.
- Test an unreleased Platform change only with `-PplatformRepository` (Decision 6), never with a copied config.
- Reusable workflows are pinned to an exact `@vX.Y.Z`; never `@v1`, never `secrets: inherit`.
- Hand a branch off with `scripts/merge.sh <branch> '<conventional commit message>'`; never merge into `main`.
- Keep concepts, plans and analyses in the ignored `docs/concepts/`. Add no AI attribution to commits or pull requests.
<!-- END platform-agents -->
