<!-- BEGIN platform-agents-backend v{{VERSION}} (managed by platform-bump; edits inside these markers are replaced) -->
## Backend rules for agents (Platform {{VERSION}})

The stack of Platform {{VERSION}}, taken from its catalog and enforced by the build: Java {{java}} toolchain,
Gradle {{gradle}}, Spring Boot {{springBoot}}, Spring Modulith {{springModulith}}, Spring AI {{springAi}},
JUnit {{junit}}. Read versions from `libs.versions.toml` of that release, never from memory.

- Dependencies are `libs.<alias>` without a version; Boot starters, Jackson and JUnit come from
  `pl.seniordeveloper:platform-bom`. Add no BOM, `resolutionStrategy` or `*.version` property of your own: the
  Platform gates warn or fail on them.
- The conventions own toolchain, formatting, Checkstyle, coverage, PIT, SpotBugs and Sonar. Configure them in the
  `platform { }` block or through their documented properties, not through the plugins they apply.
- Tests: `test` must not need Docker. Tag Testcontainers tests `@IntegrationTest` or `@PostgresIntegrationTest`
  (`integrationTest`), slow model tests `@ModelTest` (`modelTest`, outside `check`); a flaky test is tagged
  `quarantine` only with `// quarantine: <issue-url> until YYYY-MM-DD` above the tag.
- From the repository root: `AI_AGENT=1 bash scripts/agent-gradle.sh lint` (format check and linters, no tests)
  and `format`; run tests only when asked.
- The final stage of the Dockerfile follows `templates/Dockerfile.backend` of the pinned release, and a Liquibase
  change file is `db/changelog/changes/NNNN-<slug>.yaml` with the next free prefix.
- GitHub Packages credentials: `gpr.user` and `gpr.key` in `~/.gradle/gradle.properties` locally,
  `GITHUB_ACTOR` and `GITHUB_TOKEN` on CI; never in the repository.
<!-- END platform-agents-backend -->
