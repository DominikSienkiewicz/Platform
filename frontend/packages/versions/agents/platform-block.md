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
