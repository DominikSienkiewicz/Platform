# Changelog

Changes to the published Platform artifacts, newest first, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. All artifacts share one
version. The [release and versioning contract](docs/adr/0002-release-and-versioning-contract.md)
defines the numbering: a release that needs action in consumer repositories bumps the MINOR
version in the 1.x line and lists that action under **Consumer action required**, which every
version has, saying "None." when nothing is required.

Sections from 1.5.26 to 1.5.31 were reconstructed from the release history on 2026-10-18.

Gaps in the history: 1.5.0 was never published, so use 1.5.1; 1.3.13 has no tag; test-fixtures
1.0.2 to 1.1.0 come from an abandoned auto-versioning model and have no matching release of the
other artifacts. Since 1.6.0 `release.yml` fails unless every artifact carries the released version.

## [Unreleased]

### Consumer action required

- The roadmap toolkit (BookOfStyling, SkillSprintPlus) is marked *experimental*: only its marker contract
  is stable. Re-copy `templates/roadmap/scripts/**` and the new issue form
  `templates/roadmap/.github/ISSUE_TEMPLATE/roadmap-item.yml`; `roadmap-unblock.yml` now runs only for
  issues closed as completed, one run at a time. Run the marker self-heal with `--preview <ID>` and
  `--dry-run` first: it rewrites titles and bodies, now from the Backlog Handoff table.
- `deploy.yml` reads `SSH_HOST`, `SSH_USER`, `SSH_KEY` and `SSH_KNOWN_HOSTS` as secrets of the
  `production` environment, whose deployment branch policy admits only `release`; its preflight no
  longer checks them. Sync `templates/setup-gh-deploy.sh` into `scripts/`, run it once (it creates the
  environment, the policy and the secrets), then delete the repository-level `SSH_*` secrets it lists,
  and drop `SSH_*` from the caller's `secrets:` block. A job of your own that uses the SSH key needs
  `environment: production`. A private repository needs GitHub Pro, Team or Enterprise for
  environment secrets. `--with-release` now requires a pull request without an approval.
- `frontend-ci.yml` with `strict: true` requires a nonempty `format:check` script and runs it before
  lint. No caller uses `strict` today; one that does adds the script, for example with
  `@dominiksienkiewicz/prettier-config` as `docs/consuming.md` shows.
- The catalog drops `libs.jimfs`, `libs.java.diff.utils`, `libs.openai.java.client.okhttp` and
  `libs.anthropic.java.client.okhttp`, which no consumer declared. A build that uses one fails to
  resolve the alias; add the library to the Platform catalog first, as for any new library.
- `AbstractLiquibaseChangelogTest` parses the master changelog and its includes with Liquibase instead
  of looking for the word `databaseChangeLog`. A typo in an include path or invalid YAML now fails the
  fast test instead of the Testcontainers context test; fix the file the failure names.
- `platform-bump` now moves your callers of Platform's reusable workflows to the bumped tag,
  `@v1` included, and a `platform-ref:` input of `deploy.yml` with them. Review the workflow diff
  of your first bump: a caller on `@v1` moves to an exact tag and stops floating.
- `platformDependencyCheck` now also governs dependency constraints, every declarable bucket
  (`compileOnlyApi`, `developmentOnly`, `testAndDevelopmentOnly`, `testFixtures*` and custom
  source sets) and `pl.seniordeveloper` artifacts. Remove explicit versions from those
  declarations, or declare the dependency through `libs.<alias>`.
- `check` now fails when `coverageMinimum` is above 0 and no test task produced JaCoCo data,
  for example in a module without tests or with every test task excluded. Before, the gate was
  skipped and `check` stayed green. Add tests or set `coverageMinimum=0` for such a module.
- `check` now fails when the final `FROM` of the project's Dockerfile runs an older Java than
  the toolchain (27), which before surfaced only as `UnsupportedClassVersionError` at the
  post-deploy health gate. Move the final stage to the image in `templates/Dockerfile.backend`
  (`sapmachine:27-jre`) before taking this release; `platform-bump` does it for a final
  `eclipse-temurin:<N>-jre` or `-jdk` stage (migration `1.6.0-runtime-image-27`) and names any other
  image for a manual fix.
- Callers of `frontend-ci.yml` must grant `packages: read`. The workflow now requests it, so the
  automatic `GITHUB_TOKEN` fallback can read `@dominiksienkiewicz/*`, and a caller that grants only
  `contents: read` fails with `startup_failure`. Pass `gpr_token` explicitly as shown in
  `docs/reusable-workflows.md`. `platform-bump` adds `packages: read` to the callers of `backend-ci.yml`
  and `frontend-ci.yml` (migration `1.6.0-caller-packages-read`) and names a `permissions:` it cannot
  edit for a manual fix.
- `coverageMinimum` must be a decimal between 0 and 1. A value such as `80` or `0,8` now fails
  the build instead of setting a threshold of 80 or crashing with a parse error.

- `platform-versions-check` now requires every `@dominiksienkiewicz/*` pin to be exact and equal to
  the installed `@dominiksienkiewicz/versions` release, and it governs `optionalDependencies`. A
  caret on a Platform pin, pins from two releases, or an optional dependency off the canon now
  fails `frontend-ci`. `scripts/platform-bump.sh` already writes consistent pins; fix hand edits.

- Every job of the reusable workflows has a time limit instead of GitHub's 360 minutes: backend-ci 30,
  frontend-ci 20, security-scan and container-scan 15, semgrep and scorecard 10, roadmap-unblock 5,
  deploy 30 for the build and 20 for the deploy. A caller whose job runs longer passes
  `with: { timeout-minutes: N }` (`build-timeout-minutes` and `deploy-timeout-minutes` in deploy.yml).

### Added

- `templates/agent-gradle.sh` coordinates separate Gradle invocations: with `AI_AGENT` on, a run of
  `test`, `integrationTest`, `check` or `build` takes one of `AI_AGENT_TEST_SLOTS` (default 3)
  machine-wide slots and waits for one, reclaiming slots of dead processes. `templates/agent-preflight.sh`
  says whether the machine can take more agents (exit 0, 1 or 2) on macOS and Linux. Re-copy
  `scripts/agent-gradle.sh` to get the slots.
- `templates/worktree-new.sh <type> <description>` starts a feature branch in its own worktree under
  `.worktrees/`, named `<type>/<description>-YYYY-MM-DD` from the latest `origin/main`, and
  `templates/worktree-status.sh` shows every worktree with whether `merge.sh` can take it. Copy them to
  `scripts/` next to `merge.sh` if you want them.
- Platform's CI has duration budgets: after every CI run, `ci-budget.yml` compares each job with
  `.github/ci-budgets.json`, warns on an overrun and lists every job in its summary. A test fails when a
  `ci.yml` job has no budget.
- Platform's CI runs the frontend workspace on Node 22.13.0, the floor its packages declare, as well as
  on Node 24. A weekly `upstream-canary.yml` builds the `java-library` starter on the current Gradle
  release candidate and reports when `eclipse-temurin:<java>-jre` exists and passes the container-scan
  gate, each in one issue that later runs update.
- `backend-ci.yml` uploads the test and Checkstyle reports of every module, not only the root's, and a
  failed job annotates each failed test and Checkstyle violation at its line and summarises them with
  Gradle's "What went wrong". `frontend-ci.yml` names the script that failed. A multi-module consumer
  can drop the block that moved its reports into the root build directory.
- `scripts/preview-on-consumer.sh <consumer>` runs an unreleased Platform on a real consumer: a
  `-canary` version of the four modules in a temporary repository, the consumer's pins rewritten in a
  throwaway worktree, and Gradle on the fast lane (`docs/local-development.md`).
- Every GitHub Release carries the release as attested files that need no credentials:
  `platform-maven-repo-X.Y.Z.zip` with all four Maven modules, the npm tarballs and `SHA256SUMS`.
  `release.yml` builds the `spring-app` starter from the zip alone, without a token, and the README
  shows how (`-PplatformRepository=file://…`).
- `platform-bump` verifies the attestation of the package it downloads before it uses it, for targets
  from 1.6.0 on, and stops with nothing changed when it does not verify (`--skip-provenance "<reason>"`
  overrides it; without `gh` it warns).
- Every Platform pull request gets a consumer impact report (`consumer-impact.yml`, `scripts/canon-diff.py`):
  the catalog, the frontend canon, the reusable workflow contract and the copied templates compared as
  parsed values. A change that needs consumer action labels the pull request `consumer-action`.
- `platform-workflows-check`, a bin of `@dominiksienkiewicz/versions`, holds every caller of a Platform
  reusable workflow to the release's caller contract: the permissions it grants (its own block, else
  the workflow's), its inputs, required inputs and secrets, and an exact ref. It exits 1 on an error;
  `platform-bump` runs it against the target release as a report.
- Consumer action recorded in history: `release.sh` refuses a patch, or a section that says `None.`,
  when a commit since the previous tag carries a `Consumer-Action:` trailer, a `!` or a
  `BREAKING CHANGE:` footer. `scripts/release-notes.sh <range>` drafts the CHANGELOG section from
  first-parent subjects and those trailers, and a `pr-title` job in `ci.yml` checks pull request
  titles with the Conventional Commit pattern of `release.sh`.
- `release.yml` proves every release consumable (new `verify-consumable` job): the `java-library` and
  `spring-app` starters resolve it from GitHub Packages with an empty Gradle home, test-fixtures and
  security-starter included, and every public npm package installs with the files it declares.
- Upgrade migrations: `platform-bump` runs the migrations of the target release from its downloaded
  package, idempotent edits of the working tree that carry out a consumer action. The first three add
  `packages: read` to the callers of `backend-ci.yml` and `frontend-ci.yml`, move a final
  `eclipse-temurin` stage below 27 to `sapmachine:27-jre`, and remove `overrides` the canon no longer
  lists (on every bump). A shape a migration does not recognise is reported for a manual fix.
- `platform-bump` is transactional. Before writing anything it checks the tools it needs, that the
  files it rewrites carry no uncommitted changes (`--allow-dirty` overrides) and that GitHub accepts
  the token, and exits 2 otherwise. A failure after the first write restores every file it changed.
  `--dry-run` prints the lines a bump would change without writing them or running Gradle.
- `releases/yanked.txt` lists releases `platform-bump` no longer offers: a bump without a version skips
  them, and an explicit one needs `--allow-yanked`. It starts with 1.3.4 and 1.5.1–1.5.3, which were
  published without the catalog variant or the plugin markers. `docs/runbooks/rollback.md` describes
  yanking, fixing forward and pinning a consumer back.
- Contract-first OpenAPI kit (*incubating*; [docs/api-contracts.md](docs/api-contracts.md)), for a
  hand-written spec committed to the repository:
  - `AbstractOpenApiContractTest` in `platform-test-fixtures` fails when the Spring MVC controllers and
    the spec describe different operations, or the spec lacks an `operationId`, `responses` or a local
    `$ref` target. It runs without Docker.
  - `@dominiksienkiewicz/openapi` with `platform-openapi-gen` and `platform-openapi-check`: TypeScript
    types generated from the spec named in `package.json#platform.openapi`, and a check that fails on
    stale ones. Strict `frontend-ci` runs the check for a repository that configures
    `platform.openapi`; no caller does yet.
  - `createApiClient<paths>()` in `@dominiksienkiewicz/api-client` types paths, request bodies and
    responses by the generated `paths` interface. Types only; the package stays private.
  - Reusable `api-contract.yml`: oasdiff compares the spec of a pull request with its base, writes the
    changelog to the job summary and fails on a breaking change unless the pull request carries the
    `api-breaking` label. Platform's CI runs it on a compatible and a breaking fixture pair.
- Platform's CI analyses `platform-test-fixtures` and `platform-security-starter` in SonarQube Cloud
  with `seniordev.quality-conventions`, the setup consumers use. The job skips with a notice until the
  `SONAR_TOKEN` secret exists (`RELEASING.md`).
- `templates/merge.sh` warns when the source branch re-applies commits whose changes are already on the
  target, lists them and prints the command that drops the copies. It still integrates the branch and
  keeps its exit code. Sync the copy in `scripts/`.
- Every published jar, the catalog TOML and every npm tarball carry a GitHub artifact attestation
  (SLSA build provenance) from `release.yml`. Verify a file with
  `gh attestation verify <file> --repo DominikSienkiewicz/Platform`, as `docs/consuming.md` shows.
- `platform-templates-check`, a bin of `@dominiksienkiewicz/versions`, compares the scripts and the
  `.editorconfig` a repository copied from `templates/` with the canon of its pinned release and prints
  the command that restores each drifted or missing file. `platform-bump` runs it after every bump. It
  only reports and never fails the bump.
- `docs/compatibility.md`: the Java toolchain, runtime image, Gradle, Spring and frontend versions of
  each release, back to 1.4.0, with a test that fails when the top row drifts from the catalog. Every
  npm package declares `engines.node` `>=22.13`, so npm warns on an older Node at install time.
- `@dominiksienkiewicz/prettier-config` (*incubating*): Prettier with `prettier-plugin-tailwindcss`, the
  configuration BookOfStyling already uses.
- `docs/consuming.md` shows how to adopt the incubating catalog bundles and the security starter, with
  the properties that replace the two existing `SecurityConfig` variants.
- `platformBomOverrideCheck` on `check` warns about every BOM version property a consumer sets outside
  the platform (`extra["jackson-bom.version"]`), and `platform-bump` lists the `useVersion`, `force`,
  `strictly` and `extra["….version"]` overrides of the backend after every bump. Neither fails the build.
- `security-scan.yml` gains `only-if-deps-changed` (default `false`) and `deps-pattern`: a push or pull
  request scans only when a dependency manifest changed, schedules and manual runs always. Callers can
  drop the `changes` job they copied.
- Platform's CI runs the reusable `backend-ci.yml` on the `java-library` starter, on every push and
  every Monday at 04:00 UTC, so a broken workflow or a drifted runner shows up here before it reaches
  a consumer. Releases wait for it too.
- Reusable `platform-bump.yml`: run it on a schedule and it bumps the repository to the newest Platform
  release of the current MAJOR and opens a pull request with the diff, the release notes and the
  consumer actions. The caller grants `contents: write`, `pull-requests: write` and `packages: read`.
- `frontend-ci.yml` with `run-e2e: true` uploads the Playwright report and traces as the artifact
  `playwright-report-<run id>`, kept for seven days.
- `canon-cve-scan.yml` scans the versions Platform imposes every Monday before the consumers' scans:
  a lockfile resolved from the frontend canon, and the SBOM of `gradle/canon-probe`, which applies
  the convention plugins from source to every catalog library. `docs/versions.md` describes the
  CVE response: a patch release within seven days, three for a CRITICAL finding.
- `docs/consuming.md` opens with Prerequisites, a Quickstart and Verify, ends with a Troubleshooting
  table, and its snippets paste into real consumer layouts. `templates/npmrc` is the canonical
  `frontend/.npmrc`.
- `docs/reusable-workflows.md`: the caller contract of every reusable workflow (permissions, secrets,
  variables and a snippet). Every workflow input and secret has an English description.
- `docs/reference.md`: every task, property and default the convention plugins add, the security
  starter properties and a snippet per test fixture. The README shows how a release reaches the
  registries and the consumer pins.
- `platform-test-fixtures` and `platform-security-starter` publish sources and javadoc jars, the convention
  plugins a sources jar, and every
  `platform.security.*` and `platform.cors.*` property has an IDE description.
- Every release gets a GitHub Release whose notes are its CHANGELOG section, and an annotated
  version tag carrying the same notes.
- `platform-bump` prints the notes of every release it crosses and repeats their consumer
  actions at the end. The stub runs the installed copy of the bin, so the notes appear from the
  bump after the one that installs this release.

- The frontend canon gains `@eslint/js` 10.0.1 and `globals` 17.13.0.

- `docs/security-scanning.md`: the gates of every scan and a procedure for accepting a finding,
  with `templates/grype.yaml`. `security-scan.yml` fails on a `.grype.yaml` entry whose
  `# expires:` date has passed and warns on one without a date, and gains an `only-fixed` input
  (default `false`, the behaviour so far).

- Platform runs its own `scorecard.yml` and `semgrep.yml` on itself from `self-scan.yml`: Scorecard on
  every push to `main` and weekly, with published results; Semgrep also on pull requests. A change
  to either workflow now runs in Platform before consumers get it.

### Changed

- The shared Renovate preset waits three days after a GitHub Actions or Docker release before it opens
  a pull request, and lets security fixes through at once, outside the Monday window, labelled
  `security`, with OSV alerts on.
- Everything a consumer reads is in English: the `infra/` and roadmap toolkit READMEs, the canonical
  pull request template, every npm package description, and the gate messages of `frontend-ci.yml`,
  `semgrep.yml` and `deploy.yml`. The README records the rule. Re-copy
  `templates/github/pull_request_template.md` if you want the English checklist.
- `sonar.yml` is deprecated: no consumer calls it. It keeps working for existing references; run the
  `sonar` task that `seniordev.quality-conventions` configures in the backend job instead.
- `deploy.yml` builds `bootJar` with `setup-gradle`, which on `release` reads the cache your backend jobs
  wrote on the default branch, and caches the layers of each image in the GitHub Actions cache
  (`type=gha`, `mode=max`, one scope per image). The layer cache shares the repository's 10 GB Actions
  cache with Gradle; GitHub evicts the oldest entries.
- The README no longer lists an HTTP JSON channel for `@dominiksienkiewicz/ui`: nothing builds or hosts
  one, and the npm package ships the registry sources only. Its description names its two items.
- `@dominiksienkiewicz/api-client` and `@dominiksienkiewicz/query` are private and no longer published;
  1.5.31 stays their last release in GitHub Packages. No consumer used them; adopting one makes it
  public again.
- Consumers need Gradle 9.6.1 or newer, the minimum TestKit now builds a consumer on;
  `seniordev.settings-conventions` fails an older build with the fix. `platform-bump` moves the Gradle
  wrapper to the catalog's new `gradle` entry (9.8.1), with its SHA-256, so review the wrapper diff of
  your next bump.
- The shared Renovate preset (`default.json`) covers only GitHub Actions and Docker images. Its Gradle
  and npm rules and its Platform-pin manager, which never produced a working pull request, are gone:
  those versions move with `platform-bump`. Platform's own `renovate.json` manages the catalog and the
  frontend canon, and CI validates both configs.
- Platform's CI runs shellcheck on every tracked shell script, the ones copied into consumers and
  run on the deploy host included; `bump-version.sh db new-migration` numbers changesets with a glob
  instead of parsing `ls`.
- `release.yml` fails unless every published artifact carries the released version (new
  `verify-published` job), and its tag guard reports in English.
- The canon no longer ships known HIGH or CRITICAL CVEs with a fix: `seniordev.spring-modulith-conventions`
  overrides Tomcat to 11.0.27 and Jackson to 3.1.8 and 2.21.8 above the Spring Boot 4.1.1 BOM, the catalog
  moves jsoup to 1.23.2 and the frontend canon js-yaml to 4.3.2. `scripts/platform-bump.sh` regenerates the
  lockfiles and verification metadata these versions change.
- `templates/setup-gh-deploy.sh` verifies the scanned SSH host key against the new
  `SSH_HOST_KEY_SHA256` before pushing anything, warns when it is empty, and exits non-zero when a
  `gh` call fails instead of ending with "Gotowe". Sync the copy in `scripts/`.
- Every GitHub-owned action in the reusable workflows is pinned by commit SHA with a version
  comment, like the third-party ones; the versions run are the same as before.
- Snyk runs from a digest-pinned `snyk/snyk:docker` image instead of the Snyk Docker action, which
  executed the moving `:docker` tag whatever SHA it was pinned to. In `deploy.yml` it moves to an
  advisory `snyk-advisory` job with `packages: read`, out of the job that pushes images.
- `deploy.yml` checks Platform out without a token and takes `scripts/deploy-remote.sh` from the new
  `platform-ref` input (default `v1`); set it to the tag in `uses:` so script and workflow come from
  one release. Every checkout in `deploy.yml` drops its persisted credentials, and the workflow
  declares read-only top-level permissions.
- `frontend-ci.yml` exposes `GITHUB_TOKEN` to `npm ci` only; lint, typecheck, test and build run
  without registry credentials.
- `deploy.yml`, `sonar.yml` and `roadmap-unblock.yml` declare the secrets they read, so callers can
  pass them explicitly instead of handing every repository secret over with `secrets: inherit`;
  `inherit` keeps working. `roadmap-unblock.yml` reads only `ROADMAP_PROJECT_TOKEN`, a classic PAT
  valid for 90 days at most, and no longer persists the checkout token.
- `@dominiksienkiewicz/tsconfig/next.json` no longer sets `include`, `exclude` or `paths`. TypeScript
  resolved them inside `node_modules/@dominiksienkiewicz/tsconfig`, so a consumer that did not
  redeclare them compiled nothing. Declare them in the consumer's `tsconfig.json` as
  `docs/consuming.md` shows; the one consumer of `next.json` already does.
- Platform's own frontend packages follow the version canon: `@dominiksienkiewicz/eslint-config`
  declares `@eslint/compat` and its `eslint`, `eslint-config-next` and `next` peers at the exact
  canon version, and `@dominiksienkiewicz/ui` its runtime dependencies. A consumer on the canon
  installs them unchanged; one off the canon gets a peer conflict from npm.
- `platform-versions-check` names the canon release it read (`@dominiksienkiewicz/versions@X.Y.Z`),
  reports drift in English and ends with a fix that exists in consumers: run
  `scripts/platform-bump.sh X.Y.Z` from the repository root. It pointed at `./platform-bump.sh`, which
  no consumer has, and at the Platform maintainer's `./release.sh`.
- `platform-bump` also bumps a template-style `platformVersion=` pin in `backend/gradle.properties`
  (or a root `gradle.properties`) and fails when it finds no pin instead of reporting success.
- `buildAndPublishLocal.sh` prints the consumer command with `-PplatformRepository`, and the docs
  replace the non-existent `npm run platform:link` with `npm install --no-save <path>`.
- `platform-bump` without an argument stays in the consumer's current MAJOR version and only
  reports a newer MAJOR; crossing it takes an explicit version.
- `platformDependencyCheck` messages are in English and name the fix: the `libs.…` alias to
  use, a BOM-managed version to remove, or a library to add to the Platform catalog first.
- `platform-catalog` gains a `spotbugs` version entry, the canon of the SpotBugs
  `toolVersion` in `seniordev.quality-conventions`.
- The catalog's `platform` placeholder is now `0.0.0-injected-at-publish`, a version that cannot
  resolve, instead of the real release `1.4.3`. Published catalogs carry the injected
  release version as before.
- The JVM starters in `templates/jvm/` are pinned to the latest release.
- `check` prints the effective coverage threshold and where it came from.

### Fixed

- `extractCheckstyleConfig` and `extractSpotbugsConfig` no longer capture the plugin script object in
  their actions, which the configuration cache cannot serialize; a consumer that turns the cache on
  no longer fails `check` on them.
- Roadmap toolkit: auto-unblock reads the older SkillSprintPlus marker layout, takes the status from the
  `status:*` label, ignores prerequisites closed as not planned, and fails instead of claiming changes it
  did not make. The generator stops before creating anything when the issue snapshot fails or is
  truncated, stops on a duplicate roadmap ID, keeps an auto-unblocked status and ticked criteria on
  re-sync, keeps dependency links under `--only`, reconciles native `blocked_by` links, selects the board
  by number and reports write errors; project setup no longer creates a twin of a closed board. Titles,
  Risk and Notes come from the roadmap's Backlog Handoff table and Risk field, streams from
  `ROADMAP_STREAMS`, and the body names `ROADMAP_DOC_PATH`.
- The platform Checkstyle config accepts an empty arrow `case` block, `case 1 -> {}`, which
  google-java-format produces and `WhitespaceAround` rejected, so `spotlessApply` and `checkstyleMain`
  no longer contradict each other on it. A corpus of formatter output now guards the pair.
- `templates/bump-version.sh db new-migration` writes the repository name as the changeset author when it
  runs from a worktree such as `<repo>/.worktrees/<name>`; it wrote the worktree name. Sync the copy in
  `scripts/`.
- `platform-bump` rewrites a settings plugin pin with extra spaces around `version`, and fails when a
  Platform pin in `backend/settings.gradle.kts` is written in a form it cannot rewrite, instead of moving
  the catalog and leaving the plugin behind. An `npm pack` error other than a missing release (an E401,
  a network failure) now stops the bump with npm's message; before, every error read as "an old
  Platform release" and the bump went on without the frontend canon.
- `@dominiksienkiewicz/api-client` keeps headers passed as a `Headers` instance or an array of pairs,
  which the object spread dropped, and a call's header replaces a default of the same name in any case.
- `AbstractFlywayMigrationTest` checks every `db/migration` root on the classpath, jars included, with
  subdirectories, and reports duplicate versions. It read only the first root, so test resources hid the
  production migrations, and it ignored subdirectories and failed on migrations packaged in a jar.
- `platform-security-starter` fails at startup on `platform.cors.allowed-origins=*` with credentials
  allowed, instead of on the first CORS request. Its CORS-source choice, `http-basic=false` and the
  replacing `permitted-paths` are pinned by tests and documented.
- `platform-security-starter` now orders its chain before Spring Boot's default web and management
  security. Before, Boot's default chain registered first in a real application and the starter backed
  off, so `platform.security.mode=permit-all` answered 401 everywhere; a non-web application no longer
  fails to start with the starter on the classpath.

## [1.5.31] - 2026-10-14

### Consumer action required

- Callers of `backend-ci.yml` must grant `packages: read` in their workflow `permissions`. A
  reusable workflow cannot request more than its caller grants, so a caller with only
  `contents: read` fails with `startup_failure`. Because consumers call it through the moving
  `@v1`, this reached them on their next CI run, without a bump.
- After the bump, regenerate `gradle.lockfile` and, where present,
  `gradle/verification-metadata.xml`: the Boot, Modulith and Spring AI BOMs changed and the
  `netty.version` and `postgresql.version` overrides were removed. `platform-bump` does both.

### Changed

- Backend baseline: Spring Boot 4.1.1, Spring Modulith 2.1.1, Spring AI 2.0.1, Gradle 9.8.1.
  Boot 4.1.1 manages Netty 4.2.17.Final and PostgreSQL 42.7.13, so the earlier CVE overrides
  were dropped.
- Frontend canon: Next and `eslint-config-next` 16.4.0.
- Gradle wrapper distributions include the official SHA-256 checksum.
- `platform-security-starter` and `platform-test-fixtures` import the same source catalog for
  their BOMs.

### Added

- `-PplatformRepository=<uri>` puts a locally published Platform first in plugin and
  dependency resolution; without it nothing local is consulted
  ([ADR-0003](docs/adr/0003-local-platform-resolution.md)).
- `templates/jvm/java-library` and `templates/jvm/spring-app`, the starters the TestKit
  consumer suite builds.
- `frontend-ci.yml` input `strict` (default `false`), which makes every standard check
  mandatory.

### Fixed

- `@dominiksienkiewicz/api-client` preserves the HTTP status and body of error responses.
- The agent test profile caps Vitest workers.
- `backend-ci.yml` keeps package access and passes `gradle-task` arguments literally.

pnpm 12, Vitest 5 and a full OpenAPI validation and generation pipeline stay separate
migrations and are not part of this release.

## [1.5.30] - 2026-09-25

### Consumer action required

None.

### Fixed

- `seniordev.spring-modulith-conventions` manages `com.tngtech.archunit:archunit` 1.5.0 on every
  configuration, the runtime classpath included. Spring Modulith 2.1.0 pulled ArchUnit 1.4.2,
  which cannot read class-file 71, so an application built on 1.5.29 failed to start with
  "No classes found in packages" even though its tests passed.

## [1.5.29] - 2026-09-25

This release required consumer action but shipped as a patch. Under
[ADR-0002](docs/adr/0002-release-and-versioning-contract.md) it would have been a minor.

### Consumer action required

- The toolchain moved to JDK 27, so the backend runtime image must run Java 27 or later: change
  the final `FROM` of `backend/Dockerfile` to `sapmachine:27-jre`, as in
  `templates/Dockerfile.backend`. An older image fails at start with
  `UnsupportedClassVersionError`.
- CI needs a JDK 27 toolchain. The reusable `backend-ci.yml`, `deploy.yml` and `sonar.yml`
  install it themselves (input `toolchain-java-version`, default `27`); a workflow of your own
  must install it.

### Changed

- `seniordev.java-conventions` compiles with the JDK 27 toolchain. Lombok is overridden to
  1.18.48 above the Boot BOM, because 1.18.46 fails on javac 27.
- PIT is pinned to 1.30.0, the first release that reads class-file 71.
- CI installs the toolchain with `actions/setup-java` instead of Foojay, which offered only an
  Alpine build of Temurin 27 for Linux
  ([ADR-0004](docs/adr/0004-consumer-toolchain-jdk-27.md)).
- `templates/Dockerfile.backend` runs on `sapmachine:27-jre`.

## [1.5.28] - 2026-09-24

### Consumer action required

None.

### Fixed

- `seniordev.java-conventions` pins google-java-format 1.36.1. Spotless otherwise picked its
  default from the JVM running Gradle, which on JDK 27 was a release that crashes on javac 27.

### Changed

- The README became a router to reference documents: `docs/consuming.md`,
  `docs/local-development.md` and `docs/versions.md`.

## [1.5.27] - 2026-08-10

### Consumer action required

None.

### Fixed

- `platform-bump` regenerates `gradle/verification-metadata.xml` in two Gradle passes, so the
  checksums of metadata resolved outside the `build` graph are recorded too. A single pass left
  `junit-bom-<version>.pom` unverified and CI failed on a cold cache.

## [1.5.26] - 2026-08-10

### Consumer action required

None.

### Fixed

- The JUnit (6.1.3) and ArchUnit (1.5.0) versions in `seniordev.spring-modulith-conventions`
  match the catalog again. In 1.5.25 they drifted apart, so `platformDependencyCheck` failed in
  every Spring consumer.
