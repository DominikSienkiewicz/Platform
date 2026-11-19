<!-- BEGIN platform-agents v{{VERSION}} (managed by platform-bump; edits inside these markers are replaced) -->

## Platform rules for agents (Platform {{VERSION}})

For a repository that pins [DominikSienkiewicz/Platform](https://github.com/DominikSienkiewicz/Platform) {{VERSION}}.
The full rule sheet of that release: https://github.com/DominikSienkiewicz/Platform/blob/v{{VERSION}}/docs/consumer-agents.md

- Platform owns the frame: Java, Gradle, the Spring BOMs, the libraries in `libs` and the frontend canon. Never
  give them another version; `platformDependencyCheck` and `platform-versions-check` fail the build.
- A library the frame does not know belongs to this repository: Gradle `appLibs` (`gradle/app.versions.toml`),
  frontend an exact version in `package.json`. A library a Spring or Platform BOM manages takes no version.
- Gate failures carry a code such as `[PLAT-DEP-002]` with a link; follow the fix it names.
- Run Gradle through `AI_AGENT=1 bash scripts/agent-gradle.sh <tasks>`. The default gate is `lint` and `format`;
  run tests only when asked.
- Write the test before the code: run only that test (`--tests <Class>`) to see it red in its assertion, then
  green; run whole suites only when asked. A bug fix starts with a test that reproduces it, in one `fix:` commit.
  Skills: `/platform:tdd-feature`, `/platform:tdd-bugfix`, `/platform:ddd-modeling`.
- Test an unreleased Platform change only with `-PplatformRepository` (Decision 6), never with a copied config.
- Reusable workflows are pinned to an exact `@vX.Y.Z`; never `@v1`, never `secrets: inherit`.
- Hand a branch off with `scripts/merge.sh <branch> '<conventional commit message>'`; never merge into `main`.
- Keep concepts, plans and analyses in the ignored `docs/concepts/`. Add no AI attribution to commits or pull requests.

<!-- END platform-agents -->
