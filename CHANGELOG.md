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
1.6.0 itself has only its Maven artifacts: the npm publish failed, so it has no npm packages, no GitHub
Release with assets and no `v1` move. 1.7.0 is tagged but was never published: its release gate failed
before any artifact went out, so use 1.8.0, which replaces both.

## [Unreleased]

### Consumer action required

None.

### Added

- Catalog aliases without a version, managed by the Spring Boot BOM through `platform-bom`: `boot-starter-jdbc`,
  `boot-test-jdbc`, `postgresql`, `jackson-databind` and `jackson-dataformat-yaml` (Jackson 3). A module that
  does not apply the Spring conventions takes their versions from `implementation(platform(libs.platform.bom))`.
- Catalog entry `picocli` 4.7.7, the command-line parser for consumers that ship a CLI without Spring.

## [1.8.1] - 2026-10-21

### Consumer action required

None.

### Fixed

- The post-release checks `verify-consumable` (`scripts/verify-consumable.sh`) and `verify-bundle` (`release.yml`)
  give the `spring-app` starter the Gradle wrapper of `java-library` inside its own `gradle/` directory. Since
  `spring-app` gained `gradle/gradle-daemon-jvm.properties`, `cp -R` nested the wrapper in `gradle/gradle/wrapper`,
  so both checks of 1.8.0 failed with `Unable to access jarfile …/gradle/wrapper/gradle-wrapper.jar`; the published
  1.8.0 artifacts are not affected.

## [1.8.0] - 2026-10-21

### Consumer action required

1.7.0 was never published, so a repository on 1.6.0 also takes the consumer actions of 1.7.0 below. They have
no migration (manual or none); `platform-bump` runs every migration after the pinned version up to 1.8.0.

- Gradle runs on JDK 27, the only JDK Platform now builds, tests and supports Gradle on
  ([ADR-0034](docs/adr/0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md)). `build-logic` is Java 26 bytecode
  (the highest target of the Kotlin embedded in Gradle 9.8.1), so a daemon on JDK 25 stops with
  `UnsupportedClassVersionError` (`class file version 70.0`) while the plugins load. The migration
  `1.8.0-gradle-jdk-27` moves a literal `java-version` below 27 in the callers of Platform's reusable workflows and
  `java=` in `.sdkmanrc` and `backend/.sdkmanrc` to `27-tem`. Callers that leave `java-version` unset get 27 from the
  new default. Manual: regenerate `gradle/gradle-daemon-jvm.properties` with
  `./gradlew updateDaemonJvm --jvm-version=27` (the migration names the file), raise any other `setup-java` that
  runs Gradle (the migration names each one), and point a local `JAVA_HOME` at JDK 27.
- The oldest supported consumer Gradle is 9.8.1, up from 9.6.1, which cannot start on JDK 27 (Groovy:
  "Unsupported class file major version 71"); `seniordev.settings-conventions` fails an older build with the fix.
  `platform-bump` moves the wrapper to 9.8.1 (automatic).
- `platform-doctor` reports PD010 as a failure for a `java` on PATH older than 27, where it accepted 25 (none; the
  fix is the item above).

### Changed

- One JDK everywhere: the catalog's `java` (27) runs Gradle in every Platform workflow, compiles `build-logic` and
  Platform's Java modules (`test-fixtures` and the starters no longer override the toolchain to 25), and is named by
  the SDKMAN files, both devcontainers and the daemon JVM criteria of the JVM starters. The `java-version` input of
  `backend-ci.yml`, `deploy.yml`, `platform-bump.yml`, `security-scan.yml` and `sonar.yml` defaults to `27`; the
  `toolchain-java-version` input stays. ADR-0034 supersedes ADR-0004, and `templates/tests/jdk-everywhere.test.sh`
  fails when any of these JDKs leaves the catalog's `java`.

### Fixed

- The `frontend-image` job of `ci.yml` asks the registry whether the release it pins published each
  `@dominiksienkiewicz/*` package (`npm view <name>@<version>`), not only the release tag. 1.6.0 carries its
  packages at 1.6.0 in git, but its npm publish failed, so the job tried to install them and the release gate of
  1.7.0 failed with `No matching version found for @dominiksienkiewicz/eslint-config@1.6.0`; nothing of 1.7.0 was
  published. A package missing from the registry (E404) now skips the image with a notice; any other registry
  error fails the job.
- `backend-ci-smoke` in `ci.yml` builds the `java-library` starter on a Platform version GitHub Packages really has.
  The starter pin stayed at 1.7.0, which was never published, so the smoke failed on every commit after it with
  `Plugin [id: 'seniordev.settings-conventions', version: '1.7.0'] was not found`, and the release commit of the
  next version would have failed the same way on its parent's pin. `smoke-platform-version` now asks GitHub
  Packages for the versions of the `settings-conventions` marker and, when the chosen version is missing, builds on
  the newest published version below it with a notice; an API error or no published version fails the job.

## [1.7.0] - 2026-10-21

### Consumer action required

- The container guard of `platform-test-fixtures` now fails by default: a platform container
  (`PlatformSharedPostgresContainer`, `PlatformPostgresContainer`, `PlatformOllamaContainer`) configured under the
  unit `test` task throws `IllegalStateException` before it starts, where 1.6.0 printed a warning. Tag such a test
  class `@IntegrationTest` or `@PostgresIntegrationTest`. A repository that needs time sets the opt-out
  `platform.test.guard=warn` in `gradle.properties` (or `-Pplatform.test.guard=warn`), which the Java conventions
  now pass to every test JVM; a value other than `warn` or `fail` fails with a message that names it (manual).
- The `platform-agents` block of `AGENTS.md` gains a test-first rule (red and green observed by running only the
  test being written, whole suites on request, a bug fix starting with a reproducing test) and names the skills
  `/platform:tdd-feature`, `/platform:tdd-bugfix` and `/platform:ddd-modeling`; `platform-bump` replaces the block
  (none).
- The new knobs are opt-in: the `red-proof` input of `backend-ci.yml` defaults to `false`, and without
  `platform { mutation { threshold } }` or `platform.mutation.threshold` PIT keeps its own default of no threshold.
  To use them, set `red-proof: true` in the caller or a threshold in `gradle.properties` (manual).

### Added

- Three Claude Code skills in the `platform` plugin, `tdd-feature`, `tdd-bugfix` and `ddd-modeling`, each a thin
  entry to its new runbook at the pinned tag: [build a feature test-first](docs/runbooks/tdd-feature.md) (an
  acceptance criterion as Given/When/Then, red observed in an assertion by running only that test, the smallest
  code, a refactor, one commit per behaviour that names the red test), [fix a bug test-first](docs/runbooks/tdd-bugfix.md)
  (a permanent regression test, one `fix:` commit) and [model a domain with DDD](docs/runbooks/ddd-modeling.md)
  (glossary, context map, the choice of building block, an ADR with rejected alternatives for each pattern, module
  boundaries verified by a test). `docs/consumer-agents.md` lists the rule, the skills and the runbooks.
- `backend-ci.yml` input `red-proof` (default `false`) and `red-proof-tasks` (default `test`): on a pull request
  the job `red-proof` runs the test classes each `fix:` commit added or changed against the production code
  (`src/main`) of the commit's parent and requires one of them to fail, with the codes `PLAT-RED-001` (no test
  class), `PLAT-RED-002` (green on the parent) and `PLAT-RED-003` (did not run there). See
  [reusable-workflows.md](docs/reusable-workflows.md#red-proof).
- `platform { mutation { threshold } }` and the property `platform.mutation.threshold`: a minimum PIT mutation
  score as a decimal between 0 and 1, rounded up to a whole percent for PIT's `mutationThreshold`; a value outside
  0..1 fails with `PLAT-MUT-001`. Unset, nothing changes ([reference](docs/reference.md#the-platform-block)).

### Fixed

- The `npm` job of `release.yml` publishes each packed tarball as `./dist/<file>.tgz`. Since 1.6.0 it passed
  `dist/<file>.tgz`, which npm reads as the GitHub shorthand `owner/repo` and tries to clone over SSH, so the job
  failed with `Permission denied (publickey)` and every job after it was skipped. Release 1.6.0 therefore has its
  Maven artifacts in GitHub Packages but no npm packages, no GitHub Release with assets (which the `platform-bump`
  stub downloads) and no `v1` move; use 1.7.0 instead. `templates/tests/release-npm-publish-path.test.sh` runs the
  publish block against an npm stub that rejects a spec that is not a path.

## [1.6.0] - 2026-10-20

### Consumer action required

Each entry ends with the migration `platform-bump` runs, `manual`, or `none` when no consumer is affected
today. Gradle builds come first, then test fixtures, the templates a repository copies, the reusable workflows,
the frontend, and last the experimental roadmap toolkit and the incubating security starter.

- `platformDependencyCheck` now also governs dependency constraints, every declarable bucket (`compileOnlyApi`,
  `developmentOnly`, `testAndDevelopmentOnly`, `testFixtures*` and custom source sets) and `pl.seniordeveloper`
  artifacts, and it compares them with the canon embedded in the plugin instead of the consumer's `libs`
  catalog. Remove explicit versions from those declarations, or declare the dependency through
  `libs.<alias>`. A `version(...)` override after `from(...)` in the `libs` catalog now fails
  (`PLAT-DEP-004`), and so does a project that applies `seniordev.java-conventions` without a catalog named
  `libs` (`PLAT-DEP-005`); no consumer does either today (manual).
- `platformDependencyCheck` warns ([PLAT-DEPR-001](docs/gates.md#plat-depr-001)) on
  `spring-boot-starter-oauth2-resource-server` and `spring-boot-starter-oauth2-client`, which Spring Boot 4 deprecates
  in favor of `spring-boot-starter-security-oauth2-resource-server` and `spring-boot-starter-security-oauth2-client`.
  A consumer that declares them renames them before the MINOR that removes the old names (manual).
- `seniordev.java-conventions` adds `platformPinCheck` to `check`: a build whose settings plugin and
  catalog are pinned to different releases now fails, naming both versions and the fix. Read both pins
  from `platformVersion` or run `scripts/platform-bump.sh` (manual). It also registers `lint` and
  `format` in every project that has no task of that name, so Touchstone can drop its root aggregator, and
  `backend-ci.yml` gains an optional `lint-task` input (default empty, so nothing runs); pass
  `lint-task: lint` for a fast first step.
- `coverageMinimum` must be a decimal between 0 and 1: a value such as `80` or `0,8` now fails the build
  instead of setting a threshold of 80 or crashing with a parse error. `check` also fails when
  `coverageMinimum` is above 0 and no test task produced JaCoCo data, for example in a module without tests
  or with every test task excluded; before, the gate was skipped and `check` stayed green. Add tests or set
  `coverageMinimum=0` for such a module (manual).
- `check` now fails when the final `FROM` of the project's Dockerfile runs an older Java than
  the toolchain (27), which before surfaced only as `UnsupportedClassVersionError` at the
  post-deploy health gate. Move the final stage to the image in `templates/Dockerfile.backend`
  (`sapmachine:27-jre`) before taking this release; `platform-bump` does it for a final
  `eclipse-temurin:<N>-jre` or `-jdk` stage (migration `1.6.0-runtime-image-27`) and names any other
  image for a manual fix.
- `seniordev.spring-modulith-conventions` imports `platform-bom` of its own release instead of the three Spring
  BOMs and its `ext` overrides ([ADR-0013](docs/adr/0013-catalog-for-aliases-bom-for-constraints.md)). The resolved
  versions do not change. Delete your own override blocks in the bump PR, such as Azimuth's `eachDependency`;
  `platformBomOverrideCheck` now lists every `*.version` property a consumer still sets (manual).
- `seniordev.java-conventions` adds the JUnit BOM, Jupiter and the launcher of the canon to the tests. Delete the
  same three lines from a backend's `build.gradle.kts` once it is pinned to this release; set
  `platform.junit.baseline=false` to keep your own (manual).
- `check` runs `platformQuarantineCheck`: a test tagged `quarantine` without
  `// quarantine: <issue-url> until YYYY-MM-DD` above the tag fails ([PLAT-QUA-001](docs/gates.md#plat-qua-001)),
  and an expired one fails on CI. `test` of the Spring conventions also leaves out tests tagged `model`, which
  run in the new `modelTest`, outside `check`. A project that registers its own `modelTest`, as Azimuth does,
  keeps it, and the convention logs that it did not add a second one (none).
- `seniordev.quality-conventions` applies `org.sonarqube` only in the root project (F-13). A multi-module build adds
  `id("seniordev.sonar-conventions")` to its root `build.gradle.kts`, which runs one analysis over the JaCoCo report
  of every module; until then no module has a `sonar` task. Touchstone is the only multi-module consumer and runs no
  Sonar step today; single-module consumers change nothing (manual).
- `seniordev.java-conventions` compiles with `-Xlint:all,-processing,-serial`, so builds print javac warnings they
  hid before; none fails unless `platform.javac.werror=true` is set (none).
- The catalog drops `libs.jimfs`, `libs.java.diff.utils`, `libs.openai.java.client.okhttp` and
  `libs.anthropic.java.client.okhttp`, which no consumer declared. A build that uses one fails to
  resolve the alias; add the library to the Platform catalog first, as for any new library (none).
- The JVM starters carry `gradle/gradle-daemon-jvm.properties` and stop a build without GitHub Packages credentials
  before the first request; an empty or whitespace-only `gpr.user`, `gpr.key`, `GITHUB_ACTOR` or `GITHUB_TOKEN`
  counts as missing, like the empty variable the devcontainer forwards when the host has none. Copy both into an
  existing backend when convenient: the criteria file, and the `pluginManagement` block of
  `templates/jvm/spring-app/settings.gradle.kts` (manual, optional).
- `AbstractLiquibaseChangelogTest` parses the master changelog and its includes with Liquibase instead of looking
  for the word `databaseChangeLog`, so a typo in an include path or invalid YAML fails the fast test instead of
  the Testcontainers context test. It also gains a second test: every file in `db/changelog/changes/` is named
  `NNNN-<slug>.yaml`, no two share a prefix, and a changeset of every file reaches the master, because
  `deploy.yml` tags the migrate image with the highest prefix there. Today's consumer changelogs pass; a
  failure names the file and the fix (manual).
- A backend that uses `spring-modulith-starter-jpa` without an `event_publication` table has an event registry
  that does not persist publications. Copy
  `templates/db/liquibase/modulith-event-publication.yaml` as the next `changes/NNNN-…` file and include it
  in the master; `AbstractSchemaValidationIT` then proves the schema (manual,
  [consuming.md](docs/consuming.md#database-migrations)).
- `templates/Dockerfile.backend` builds in layers, starts `JarLauncher` from `/app` instead of
  `java -jar /app/app.jar`, and declares a liveness `HEALTHCHECK` and `JAVA_TOOL_OPTIONS`. Re-copy it to
  `backend/Dockerfile`, then in the compose files: drop a `command:` or `entrypoint:` that names
  `/app/app.jar`; delete the backend's `healthcheck:`, which replaces the image's (a check that only opens the
  port proves little, and `sapmachine:27-jre` has no `curl`, so a `curl` check never passes); and drop a `JAVA_TOOL_OPTIONS` unless it means to replace both flags
  (manual, [consuming.md](docs/consuming.md#runtime-image)).
- `templates/.editorconfig` indents Java with two spaces, as google-java-format in `seniordev.java-conventions`
  formats it, and keeps tabs for Kotlin and `*.kts`. Re-copy it, so editors stop fighting `spotlessApply`;
  `platform-templates-check` reports a stale copy (manual).
- The pg18 image keeps its data in `/var/lib/postgresql/18/docker`, so `infra/docker-compose.yml` now mounts
  `postgres-data` at `/var/lib/postgresql`. With the old `/var/lib/postgresql/data` mount, pg18 refuses to
  start. Change the mount in your copy (manual).
- `scripts/merge.sh` refuses a merge message that is not a Conventional Commit, as `release.sh` does, and treats the
  `.kotlin/` cache as regenerable output. Re-copy it from `templates/merge.sh` when `platform-templates-check`
  reports it, and write messages such as `feat: add X` (manual).
- `platform-bump` writes managed blocks between their markers, each file created when missing: the
  `platform-agents` rules into the root `AGENTS.md`, and the stack, rules and commands of the pinned release into
  `backend/AGENTS.md` (`platform-agents-backend`; the root `AGENTS.md` when Gradle sits at the root) and
  `frontend/AGENTS.md` (`platform-agents-frontend`). Where one of those directories has no `CLAUDE.md`, it writes
  one that imports `@AGENTS.md`; an existing `CLAUDE.md` is never changed, only flagged when it lacks the import.
  After the bump, delete what those files copied from Platform, such as hand-copied "Stack (version-pinned)" or
  convention-plugin sections, whose versions go stale with every bump, and keep only
  project rules outside the markers (manual).
- `platform-bump` now moves your callers of Platform's reusable workflows to the bumped tag,
  `@v1` included, and a `platform-ref:` input of `deploy.yml` with them. Review the workflow diff
  of your first bump: a caller on `@v1` moves to an exact tag and stops floating (manual review).
- `deploy.yml` reads `SSH_HOST`, `SSH_USER`, `SSH_KEY` and `SSH_KNOWN_HOSTS` as secrets of the
  `production` environment, whose deployment branch policy admits only `release`; its preflight no
  longer checks them. Sync `templates/setup-gh-deploy.sh` into `scripts/` and make sure git ignores
  `.secrets.local` (the rule is in `templates/gitignore/root.gitignore`): the script now refuses to run
  while the file holding the PATs could be committed. Run it once (it creates the environment, the policy
  and the secrets), then delete the repository-level `SSH_*` secrets it lists, and drop `SSH_*` from the
  caller's `secrets:` block. A job of your own that uses the SSH key needs `environment: production`. A
  private repository needs GitHub Pro, Team or Enterprise for environment secrets. `--with-release` now
  requires a pull request without an approval (manual).
- Callers of `frontend-ci.yml` must grant `packages: read`. The workflow now requests it, so the
  automatic `GITHUB_TOKEN` fallback can read `@dominiksienkiewicz/*`, and a caller that grants only
  `contents: read` fails with `startup_failure`. Pass `gpr_token` explicitly as shown in
  `docs/reusable-workflows.md`. `platform-bump` adds `packages: read` to the callers of `backend-ci.yml`
  and `frontend-ci.yml` (migration `1.6.0-caller-packages-read`) and names a `permissions:` it cannot
  edit for a manual fix.
- Every job of the reusable workflows has a time limit instead of GitHub's 360 minutes: backend-ci 30,
  frontend-ci 20, security-scan and container-scan 15, semgrep and scorecard 10, roadmap-unblock 5,
  deploy 30 for the build and 20 for the deploy. A caller whose job runs longer passes
  `with: { timeout-minutes: N }` (`build-timeout-minutes` and `deploy-timeout-minutes` in deploy.yml) (manual).
- `semgrep.yml` also fails on findings of severity `CRITICAL` and `HIGH`, the newer Semgrep scale that rules such
  as `package_managers` use; `ERROR` still fails, and `MEDIUM`, `WARNING`, `LOW` and `INFO` stay log-only. Its
  summary counts every severity instead of only `ERROR`, `WARNING` and `INFO`, which hid `MEDIUM` findings.
  Azimuth's last scan listed no `CRITICAL` or `HIGH` finding; a repository whose scan lists one fixes it or
  records an exception as `docs/security-scanning.md` describes (manual).
- `frontend-ci.yml` with `strict: true` requires a nonempty `format:check` script and runs it before
  lint. No caller uses `strict` today; one that does adds the script, for example with
  `@dominiksienkiewicz/prettier-config` as `docs/consuming.md` shows (none).
- `platform-versions-check` now requires every `@dominiksienkiewicz/*` pin to be exact and equal to
  the installed `@dominiksienkiewicz/versions` release, and it governs `optionalDependencies`. A
  caret on a Platform pin, pins from two releases, or an optional dependency off the canon now
  fails `frontend-ci`. `scripts/platform-bump.sh` already writes consistent pins; fix hand edits (manual).
- The roadmap toolkit is marked *experimental*: only its marker contract is stable. A repository that
  copied it re-copies `templates/roadmap/scripts/**` and the new issue form
  `templates/roadmap/.github/ISSUE_TEMPLATE/roadmap-item.yml`; `roadmap-unblock.yml` now runs only for
  issues closed as completed, one run at a time. Run the marker self-heal with `--preview <ID>` and
  `--dry-run` first: it rewrites titles and bodies, now from the Backlog Handoff table (manual).
- The security starter's `platform.security.csrf` is now `ON`, `OFF` or `SPA`; `true` and `false` still bind, and
  its 401 and 403 bodies are `application/problem+json`. No consumer has adopted the starter (none).

### Added

- Gate codes: every Platform gate names its failure (`[PLAT-DEP-001]` …) and links its section of the new
  `docs/gates.md` at the release that produced it; `backend-ci.yml` names dependency verification and the
  coverage threshold (`PLAT-VER-001`, `PLAT-COV-003`), and `scripts/gate-failures.py` counts consumer failures
  per code locally. `templates/tests/gate-codes.test.sh` keeps the codes and the sections equal.
- A deprecation channel: `platform-deprecations.tsv` in the plugin (first entries: `spring-boot-starter-web`
  and `spring-boot-starter-aop`, replaced by their Spring Boot 4 names) and a `deprecated` map in
  `versions.json` warn with `PLAT-DEPR-001` and keep working; `-Pplatform.deprecations.mode=fail` fails the Gradle
  side. `deploy.yml` warns about the `gh_token` BuildKit secret id and `sonar.yml` about itself.
- `platformDependencyCheck` writes `build/reports/platform/dependency-check.md` and, in GitHub Actions, the job
  summary.
- `scripts/new-consumer.sh --frontend next` renders a strict Next.js frontend (canon versions, the Platform
  configs, `.npmrc`, `Dockerfile.frontend` and a `frontend-ci.yml` caller); a TestKit case builds `lint test`
  on both generated backends. `scripts/render-example.sh` and the `example` job of `release.yml` regenerate a
  public `platform-example` repository after each release once the `PLATFORM_EXAMPLE_TOKEN` secret exists.
- `scripts/canary.sh` previews the unreleased Platform on every consumer of `scripts/consumers.txt`
  locally (backend fast lane and the frontend's `platform-versions-check` on the new canon) and records
  the result for `HEAD`; `release.sh` refuses a commit without a green record unless `--skip-canary
  "<reason>"` is given, and keeps the reason as a `Canary-Skipped:` trailer. `preview-on-consumer.sh`
  gains `--frontend` and `--staging`.
- `pl.seniordeveloper:platform-observability-starter` (`libs.platform.observability.starter`, *incubating*):
  the actuator with probes, `health` and `info` exposed, `show-details=when-authorized` and an
  `application` tag as lowest-precedence defaults; Prometheus behind `platform.observability.prometheus`,
  public scraping behind `public-metrics`, ECS console logs behind `json-logs`, and a `tracing` feature
  with OpenTelemetry. The catalog gains the `observability-modulith` bundle.
- `pl.seniordeveloper:platform-web-starter` (`libs.platform.web.starter`, *incubating*): RFC 9457 Problem
  Details for every Spring MVC error (400 with `errors[]`, 409 for data conflicts, a generic 500,
  `traceId`, a legacy `message`). `contracts/problem-detail.json` is the golden body that its test and the
  api-client test share, and `contracts/problem-detail.openapi.yaml` the component for consumer specs.
- `pl.seniordeveloper:platform-bom` (`libs.platform.bom`, *incubating*): a `java-platform` that imports the
  Spring Boot, Spring Modulith, Spring AI and JUnit BOMs and carries the CVE floors (Tomcat, Jackson 3 and 2)
  and compatibility overrides (Lombok, ArchUnit) with their reasons, all from the catalog's versions
  (ADR-0013). `gradle/maven-modules.txt` is now the one list of published Maven modules.
- `platformPinCheck`, `lint` and `format` in `seniordev.java-conventions`, and the `lint-task` input of
  `backend-ci.yml`.
- `seniordev.settings-conventions` registers `platformDoctor` on the root project, compatible with the
  configuration cache: PD080 compares the settings plugin, the catalog's `platform` version and
  `platformVersion`, PD081 resolves the root project's Java toolchain and PD082 checks `coverageMinimum`.
  `platform-doctor --gradle` runs it through the wrapper and reports PD083 when the task does not run.
- `templates/Dockerfile.backend`: a `HEALTHCHECK` on `/actuator/health/liveness` through bash's
  `/dev/tcp`, falling back to `/actuator/health` while the probes are off, and
  `JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"`.
  `templates/tests/dockerfile-backend.test.sh` runs the probe against a stub HTTP server.
- `PlatformSharedPostgresContainer` in `platform-test-fixtures`: one fsync-off PostgreSQL on tmpfs for the
  whole JVM, shared by every cached Spring context through a `DynamicPropertyRegistrar` and reusable
  locally with `testcontainers.reuse.enable=true`. It is not a bean, because Spring Boot stops a container
  bean when its context closes. `AbstractTestcontainersFootprintTest` fails when more Platform PostgreSQL
  containers run at once than allowed (1 by default).
- `@PlatformPostgresDatabasePerContext` in `platform-test-fixtures`, an opt-in next to
  `@PostgresIntegrationTest`: every Spring context runs `CREATE DATABASE ctx_<n>` on the shared server and gets
  that database in `spring.datasource.*`, so two context signatures no longer see each other's tables, while
  the server stays one container per JVM. Closing the context drops its database; without the annotation the
  contexts keep sharing one database.
- `AbstractSchemaValidationIT` boots the application on the shared PostgreSQL with
  `spring.jpa.hibernate.ddl-auto=validate`, so Hibernate checks every entity, Spring Modulith's included,
  against the migrated schema. The canonical `event_publication` migrations
  `templates/db/liquibase/modulith-event-publication.yaml` and `templates/db/flyway/V__modulith_event_publication.sql`
  are validated in Platform's CI against the catalog's Spring Modulith version, and `docs/consuming.md`
  gains a "Database migrations" section.
- A reviewer's tour (`docs/tour.md`), five incident notes (`docs/notes/`: the swallowed 409, discarded
  integration coverage, two-pass verification metadata, ArchUnit and class-file 71, Foojay's musl JDK) and
  `docs/engineering-with-agents.md`, linked from the README.
- `scripts/consumer-audit.sh --adoption` compares each artifact's declared status (the README's
  *incubating* labels) with the consumers that use it, reports whether `move-v1` can retire (no `@v1`
  reference left) and names the oldest pinned release as the floor for cleaning up GitHub Packages.
- `scripts/consumer-audit.sh --lag` reports, per consumer, how many releases and days its pin is behind
  the newest tag, whether it pins a yanked release and how many `@v1` references it keeps. It reads the
  local tags and `releases/yanked.txt` and stays a local report.
- ADR-0011 (contract-first OpenAPI) and ADR-0012 (Platform's own modules in SonarQube Cloud). The ADR index
  is generated from the ADR headers (`scripts/adr-index.sh`), and CI checks it and every relative link and
  anchor of the Markdown files offline (`scripts/check-doc-links.py`).
- `platform-test-fixtures` names the test taxonomy: `@IntegrationTest`, `@ModelTest` and
  `@PostgresIntegrationTest` (the tag, `@SpringBootTest` and the shared platform PostgreSQL in one), with the tag
  names in `PlatformTestTags`. The platform containers warn when they start in the unit `test` task
  once the task names itself in `platform.test.task`, and throw with `platform.test.guard=fail`, which a
  later MINOR release makes the default.
- `PlatformArchRules`, a curated ArchUnit rule set, and the `HexagonalRules` preset in
  `platform-test-fixtures`; `AbstractModulithDocumentationTest` writes the Spring Modulith diagrams and
  canvases, which `backend-ci.yml` uploads as `module-docs-<run id>`.
- `AbstractModulithDocumentationTest` also writes `modules.mmd` after the PlantUML: a Mermaid `flowchart LR`
  that GitHub renders, with one node per application module and one edge per dependency between two modules
  (`uses`, `listens to` or `depends on`), sorted by module identifier. A subclass gets the file with no change.
  The `spring-app` starter gains two modules, `accounts` and `notifications`, joined by the `AccountOpened`
  event. The README shows their diagram, which a unit test of `platform-test-fixtures` keeps equal to
  `docs/diagrams/spring-app-modules.mmd`. `scripts/new-consumer.sh` carries the starter's sub-packages and
  rewrites their imports in google-java-format order, so `spotlessCheck` passes for any package. The starter
  change reaches new repositories only.
- `@dominiksienkiewicz/api-client` understands RFC 9457 Problem Details: a `application/problem+json`
  error sets `ApiError.problem` (typed `ProblemDetail`), and the message comes from `detail`, then
  `message`, then `title`. Bodies with only `message` behave as before.
- `scripts/new-consumer.sh` renders a new product repository from the canon in the `backend/` layout:
  the `spring-app` or `java-library` starter with your package, group and name, the wrapper, the pin, a
  `ci.yml` caller at the exact tag without `secrets: inherit`, and the canonical scripts and root files.
- `platform-doctor`, a bin of `@dominiksienkiewicz/versions`, diagnoses a consumer repository without
  changing it: Java and Node versions, the wrapper, pin coherence, workflow references, the source and
  the HTTP status of the GitHub Packages credentials, `.npmrc`, the lockfile, `.secrets.local` and the
  runtime image. Every check has an ID (`PD0xx`) explained in `docs/consuming.md`, Troubleshooting.
- `templates/Dockerfile.frontend` and `templates/frontend/next.config.ts`: the canonical Next.js
  standalone image on `node:24-slim`, installed with `npm ci --ignore-scripts` like CI, with the token
  only as the BuildKit secret `github_token` and a non-root runner. Moving a frontend onto it lets
  `deploy.yml` drop the `gh_token` secret alias in a later release.
- `deploy.yml` rolls an application layer back on the host: when the new backend, or a frontend with a
  healthcheck, does not become healthy, `scripts/deploy-remote.sh` recreates it with the previous tag
  from the local image and fails the job with `ROLLED BACK to <tag>`. Migrations are not rolled back, so
  schema changes must be expand/contract (`docs/reusable-workflows.md`).
- `platform-versions-check --fix` rewrites drifted versions and Platform pins to the installed canon,
  offline and without adding or removing entries. In GitHub Actions the guard annotates every violation
  at its line of `package.json` and writes a table to the job summary.
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
- The GitHub Release also carries the Sigstore bundle of that attestation, `platform-X.Y.Z-assets.sigstore.json`,
  for `gh attestation verify <file> --bundle` without the attestations API; OpenSSF Scorecard's Signed-Releases
  check looks for it.
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
- `@dominiksienkiewicz/prettier-config` (*incubating*): Prettier with `prettier-plugin-tailwindcss`.
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
- `codeql.yml` runs CodeQL on Platform (GitHub Actions, JavaScript/TypeScript, Java without a build, Python)
  on pushes to `main`, pull requests and weekly, with its alerts in Code scanning. OpenSSF Scorecard's SAST
  check recognises CodeQL and not Semgrep.
- `gradle-wrapper.yml` validates every `gradle-wrapper.jar` in seconds on each push to `main`, so OpenSSF
  Scorecard finds a successful validation on the latest commit and stops counting the wrappers as binaries;
  the same step stays in `ci.yml` for the release's `verify`.
- `osv-scanner.toml` next to the lockfiles of build-logic and the four library modules accepts the
  advisories of commons-lang3 3.8.1 and plexus-utils 3.3.0, which come only with Checkstyle 13 and read only
  the repository's own sources, until 2027-01-19 (`docs/security-scanning.md`).

- Test taxonomy as code (N-CAP-8): every test task passes its name in `platform.test.task`, so the container guard
  of the test fixtures knows the fast `test`; `modelTest` in the Spring conventions; a JUnit baseline with the
  `platform.junit.baseline` opt-out.
- Quarantine with a deadline (N-REL-13): `quarantineTest` (outside `check`, `ignoreFailures`), every other test
  task excludes the tag, and `platformQuarantineCheck` requires an issue and a date (codes `PLAT-QUA-001`/`002`).
  `-Pplatform.test.retry=detect` (or `PLATFORM_TEST_RETRY=detect`) applies `org.gradle.test-retry` 1.6.6 with one
  retry and `failOnPassedAfterRetry`; `backend-ci.yml` sets the variable (`-Pplatform.test.retry=off` in
  `gradle-task` turns it off) and writes a "Test health" job summary of flaky tests, the `quarantineTest`
  result and every quarantine deadline.
- Agent profile as a contract (N-SHOW-2): `platform.agent.testForks`, `platform.agent.testHeap` and
  `springContextCacheSize` override the `AI_AGENT` defaults in every mode, one `Platform agent profile:` line per
  build in agent mode, and `AI_AGENT_MAX_WORKERS` for `agent-gradle.sh` and the Vitest preset;
  [docs/agent-profile.md](docs/agent-profile.md) holds the table.
- Support window (N-REL-6): only the latest MINOR gets fixes, a pin stays at most 3 releases or 60 days
  behind, a security release is adopted within 14 days ([RELEASING.md](RELEASING.md#support-policy)). The
  settings plugin and `platform-versions-check` print one line for an older release, never a failure;
  `release.yml` stamps the tag's commit date into the plugin and into `versions.json` (`releasedAt`).
- `-Pplatform.toolchain.override=<N>` replaces the canon toolchain with a warning, and `upstream-canary.yml` gains
  a next-JDK leg that builds the starter on a Temurin early-access toolchain; its Gradle RC leg now runs the
  whole TestKit suite through `-PplatformTestGradleVersion` (N-REL-4).

- `platform { }`, a typed extension for `coverage.minimum`, `sonar.projectKey`, `mutation.targetPackages` and
  `staticAnalysis.failOnBugs` (N-DX-15). An unset field falls back to the existing property, so nothing changes for a
  build that sets none; the coverage gate prints `source: platform.coverage.minimum` when the block sets it.
- `seniordev.sonar-conventions` for the root of a multi-module build (F-13).
- `seniordev.nullness-conventions`, opt-in: Error Prone 2.50.0 and NullAway 0.14.2 in JSpecify mode fail
  `compileJava` on a null dereference in packages marked `@NullMarked`; TestKit runs it on the canon toolchain
  (N-CAP-11). The catalog gains `jspecify`, `errorprone-core`, `nullaway` and the `errorprone` plugin.
- `platform.javac.werror=true` turns javac warnings, Error Prone's included, into errors (N-CAP-11).
- Daemon JVM criteria in `templates/jvm/*`: the wrapper starts from any JDK and Gradle selects or downloads Java 25
  for the daemon; the starters' `pluginManagement` names the credential fix instead of a nested 401 (N-DX-2). An
  empty or whitespace-only credential counts as missing, so a blank `gpr.*` falls back to `GITHUB_ACTOR` and
  `GITHUB_TOKEN` and an empty variable gets the same message instead of a request with an empty token (N-DX-18).

- Security starter (N-CAP-13): `platform.security.mode=jwt` makes the application an OAuth2 resource server on
  Spring Boot's `spring.security.oauth2.resourceserver.jwt.*`, stateless, with `platform.security.jwt.authorities-claim`;
  without the resource-server dependency or a `JwtDecoder` it fails at startup and names the fix. 401 and 403 are
  `application/problem+json` with the mode's `WWW-Authenticate` challenge, and `platform.security.csrf=spa` uses
  Spring Security's `csrf.spa()`. The api-client's `xsrf` option echoes the `XSRF-TOKEN` cookie in `X-XSRF-TOKEN`.

- `platform-bump --report[=<file>]` prints the impact of the crossed releases on the repository on the engine of
  `scripts/canon-diff.py` (now `bin/canon_diff.py` in the versions package, with a TOML reader for Python 3.9),
  and `platform-bump.yml` puts it into the pull request body (N-REL-8).
- The bump always runs the logic of its target: a copy of `platform-bump` that is not the target release hands
  over to the target's bin from the release assets, checked against `SHA256SUMS` and the attestation, and the
  stub bumps a repository without a frontend the same way; `--print-target` prints the target only (N-DX-4).
- `release-draft.yml` keeps a draft GitHub Release **Next** with the notes since the last tag (N-REL-7).
- `scripts/ring-rollout.sh` bumps Touchstone first and the other consumers after its pull request is green
  (N-REL-1).
- `deploy.yml` takes `rollback-to-backend` and `rollback-to-frontend`: a dispatch redeploys tags already in GHCR
  without building (N-REL-12).
- `backend-ci.yml` takes `verify-provenance` ([PLAT-PROV-001](docs/gates.md#plat-prov-001)), and
  `reproducibility.yml` rebuilds the latest tag every week and compares every jar with GitHub Packages
  (N-REL-16).
- `templates/Dockerfile.backend` copies one image layer per Boot layer and trains an optional JDK AOT cache with
  `--build-arg AOT_CACHE=true`; `ci.yml` builds it from the `spring-app` starter and waits for `healthy` (N-CAP-5).
- `infra/docker-compose.yml` has an `observability` profile: otel-collector, Tempo, Prometheus and Grafana for an
  application on the host (N-CAP-4).

- Agent guidance (N-SHOW-1): a root `AGENTS.md` beside `CLAUDE.md`, the managed block
  `templates/agents/platform-block.md` that `platform-bump` syncs into consumers, the rule sheet
  `docs/consumer-agents.md`, runbooks under `docs/runbooks/`, and `templates/tests/agent-docs.test.sh`, which fails
  when they name a command, task, bin or path that does not exist.
- Per-directory agent blocks: `templates/agents/backend-block.md` and `frontend-block.md`, filled with the stack of
  the release `platform-bump` goes to: the catalog's Java, Gradle, Spring Boot, Spring Modulith, Spring AI and JUnit
  from `agents/stack.json`, which `scripts/agents-stack.py` generates from the catalog, and Next.js, React,
  TypeScript, Tailwind CSS, Vitest, ESLint and Prettier from `versions.json`. `sync-agents-block.py` takes the
  marker name from the template, so blocks of different names share one file, and refuses a block with an
  unfilled placeholder.
- A devcontainer with JDK 25 and 27, Node 24 and pnpm, guarded against the canon by
  `templates/tests/devcontainer.test.sh` and built by `devcontainer.yml`, which runs the build-logic suite in it
  (N-SHOW-11). Its base image is pinned by digest next to the tag.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (the Contributor Covenant by reference) and issue forms for bugs, library
  requests and adoptions (N-SHOW-13).
- ADRs 0014-0033 for every settled decision, with a decision map in `docs/adr/README.md` (N-SHOW-14).
- `scripts/docs-gen.sh` regenerates the template snippets, the workflow input tables and the npm package table of
  the docs; CI fails on a stale region (N-SHOW-15).
- A documentation site built with Zensical in strict mode by `docs-site.yml`, pinned with hashes, deployed to
  GitHub Pages once the maintainer enables it (N-SHOW-16).
- The documentation site is versioned per MINOR line (N-SHOW-16, ADR-0031 amended): `/<X.Y>/` holds the docs of the
  newest patch tag of each line from 1.6.0 on, each built in strict mode from its own tag with that tag's
  `scripts/docs-site.py`, `/unreleased/` holds `main`, and the root redirects to the newest released MINOR, or to
  `unreleased` while none exists. `scripts/docs-versions.py` assembles every version on each push to `main` and each
  release tag, because a Pages deploy replaces the whole site, and writes `versions.json` in the format of mike for
  the theme's version selector (`extra.version.provider = "mike"` in `zensical.toml`), so no further tool is
  installed. Pull requests still build only their own commit. Deploying from a release tag needs the tags allowed
  in the `github-pages` environment (RELEASING.md, "The documentation site"); `templates/tests/docs-versions.test.sh`
  checks the assembly on a fixture repository.
- `fast-check` 4.10.2 in the frontend canon, and property tests of `createApiClient` in
  `packages/api-client/test/properties.test.js`: headers in every `HeadersInit` form, the mapping of every 4xx
  and 5xx to `ApiError`, and the SPA CSRF rule, each on random inputs. OpenSSF Scorecard's Fuzzing check
  counts them.
- `frontend/osv-scanner.toml` records the accepted advisories of the frontend lockfile for OpenSSF
  Scorecard's Vulnerabilities check, with an end date and a reason (`docs/security-scanning.md`).
- `ci.yml` builds `templates/Dockerfile.frontend` from a frontend that `scripts/new-consumer.sh --frontend next`
  renders at the latest release, with the workflow's `GITHUB_TOKEN` (`packages: read`) only as the BuildKit secret
  `github_token`, and waits until the container answers on port 3000 (N-CAP-6). It builds when an input of the
  image changes, in the weekly run and in the release gate, and ends with a notice while the latest release does
  not publish every pinned `@dominiksienkiewicz/*` package at its own version. `new-consumer.sh --frontend next`
  now also renders the `public/` directory the image copies.
- A failing test of a Maven module shows its cause in the `ci.yml` log: `build-logic` logs failing tests in the
  full exception format, so a TestKit failure prints the output of the consumer build it ran, and the Gradle job
  uploads the test reports of every module as `platform-gradle-test-reports-<run id>-<attempt>` when it fails.
  Platform's own CI only; no consumer is affected.
- Claude Code skills (N-SHOW-1): a marketplace `seniordev-platform` at the repository root
  (`.claude-plugin/marketplace.json`) and one plugin, `platform` (`plugins/platform/`), with four thin skills:
  `bump-consumer`, `fix-gate-failure`, `add-library` and `test-unreleased-change`. Each reads the Platform version
  the repository pins and opens the runbook, or the `docs/gates.md` section of the `[PLAT-…]` code, at that tag, and
  holds no procedure of its own. A repository adds the marketplace at a release tag
  (`claude plugin marketplace add DominikSienkiewicz/Platform#v<version>`); the install and the skills are in
  [docs/consumer-agents.md](docs/consumer-agents.md#claude-code-skills). `scripts/check-agent-docs.py` now also checks
  the commands, paths and tag links the skills name, and `templates/tests/platform-plugin.test.sh` the manifests and
  that each skill points at its own runbook only.
- Community defaults for every public repository of the owner (N-SHOW-13): `templates/github/community/` holds a
  code of conduct, contributing guide, security policy (GitHub Private Vulnerability Reporting, like `SECURITY.md`),
  support file, pull request template and bug, feature request and question forms (blank issues off, no labels),
  free of anything specific to Platform and in the layout of a `<owner>/.github` repository, where GitHub applies them
  to each public repository that lacks a file of its own. `scripts/seed-community-health.sh <checkout-dir>` copies them
  into a local clone of that repository with no network call, commit or remote; the owner creates the repository,
  runs it and publishes. `docs/openssf-best-practices.md` maps the 67 criteria of the OpenSSF Best Practices
  *passing* level to evidence in this repository and marks what needs a decision from the owner, who earns the badge.
  `templates/tests/community-health.test.sh` guards the files, their neutrality, the issue-form gate and the script.
- A devcontainer template for consumer repositories (N-SHOW-11, *incubating*): `templates/devcontainer/` holds a
  `Dockerfile` (base image pinned by digest next to its tag, the JDK that runs Gradle, the catalog's toolchain JDK
  and Node with npm), a `devcontainer.json` and a `post-create.sh` that registers the toolchain JDK for Gradle and runs
  `npm ci --ignore-scripts` when `frontend/package-lock.json` exists and a token is set. The GitHub Packages
  credentials come from `GITHUB_ACTOR` and `GITHUB_TOKEN` through `remoteEnv`, never from the image or a file; without
  a token the script prints a hint instead. `templates/tests/consumer-devcontainer.test.sh` ties the versions to the
  daemon criteria of the starters, the catalog and `frontend/.nvmrc`, checks the credential wiring, and runs
  `post-create.sh` against a stub `npm`; the three files are optional entries of `templates/manifest.json`, so
  `platform-templates-check` reports drift where a repository adopts them. Nothing changes for a repository that does
  not (see [docs/consuming.md](docs/consuming.md#devcontainer-incubating)).
- `platform-doctor` PD032 warns when a Gradle build has no GitHub login, `gpr.user` in `~/.gradle/gradle.properties`
  or `GITHUB_ACTOR`, counting an empty or whitespace-only value as missing like the starters' preflight. With
  `GITHUB_TOKEN` set and an empty `GITHUB_ACTOR`, as in the consumer devcontainer on a host without the
  variable, PD030 and PD031 pass while Gradle stops with "No GitHub Packages credentials"; PD032 names the
  fix. It reads files and the environment only, prints no value, and is a warning, so it does not change the
  exit code. PD030 now counts an empty or whitespace-only `GPR_TOKEN`, `GITHUB_TOKEN` or `gpr.key` as missing
  too and falls through to the next source, so a blank token no longer passes PD030 and goes to PD031.

### Changed

- The canonical root `.gitignore` ignores `.secrets.local`, the values file of `setup-gh-deploy.sh`
  (`.secrets.local.example` stays tracked). The `.gitignore` files of the JVM starters are built from the root
  and backend canon, and `templates/gitignore/backend.gitignore` ignores the Eclipse/Buildship `bin/` output;
  `templates/tests/jvm-starter-gitignore.test.sh` keeps them consistent.
- `templates/agent-gradle.sh` runs `backend/gradlew` from `backend/` when the repository root has no wrapper.
- Every npm package declares the MIT licence in its `license` field, as the POMs of the Maven artifacts
  already did, so a dependency scanner sees it.
- `docs/consuming.md` states that frontend consumers use npm with a committed `package-lock.json`:
  `frontend-ci` runs `npm ci` and `platform-bump` refreshes the lockfile with npm, so a consumer on pnpm or
  Yarn fails CI, although Platform builds its own packages with pnpm.
- `platformDependencyCheck` is a typed task without `afterEvaluate`, so a dependency a later `afterEvaluate`
  adds is governed too.
- `platform-test-fixtures` and `platform-security-starter` import `platform-bom` instead of the separate
  BOMs, so the classpaths they reach get its floors: Jackson 3.1.8 instead of 3.1.5 and ArchUnit 1.5.0 on
  the runtime classpath. A consumer that locks dependencies regenerates its lockfile and verification
  metadata, as after any bump.
- `platformDependencyCheck` tells a library the Platform BOMs manage (with the managed version and the
  BOM-property escape hatch) apart from one no BOM manages; the BOMs are resolved only in the task action
  and only when such a line exists.
- Platform's TestKit suite runs every consumer build with `--configuration-cache`, `--warning-mode=all` and
  `-Pplatform.deprecations.mode=fail`, fails when a Gradle deprecation comes from the Platform conventions (the
  PIT plugin still calls the deprecated `Configuration.setVisible`, so `--warning-mode=fail` waits for its
  fix), passes the toolchain with `-D` instead of the deprecated `-P`, and asserts that a second java-library
  run reuses the configuration cache. `platformBomOverrideCheck` no longer calls the deprecated
  `Project.getProperties`.
- `PlatformPostgresContainer` is deprecated in favour of `PlatformSharedPostgresContainer`: as a
  `@ServiceConnection` bean it starts one container per cached context signature. It keeps working
  unchanged.
- The versions the convention plugins impose (toolchain, quality tools, BOMs and the overrides above the
  Boot BOM) are generated from the catalog into `PlatformVersions` when `build-logic` compiles, instead
  of literals mirrored in the plugin sources; a bump is one catalog entry. The versions consumers get
  are unchanged.
- The shared Renovate preset waits three days after a GitHub Actions or Docker release before it opens
  a pull request, and lets security fixes through at once, outside the Monday window, labelled
  `security`, with OSV alerts on.
- Everything a consumer reads is in English: the `infra/` and roadmap toolkit READMEs, the canonical
  pull request template, every npm package description, and the gate messages of `frontend-ci.yml`,
  `semgrep.yml` and `deploy.yml`. The README records the rule. Re-copy
  `templates/github/pull_request_template.md` if you want the English checklist.
- `sonar.yml` is deprecated: no consumer calls it. It keeps working for existing references; run the
  `sonar` task that `seniordev.quality-conventions` configures in the backend job instead.
- The convention plugins move to the Sonar Gradle plugin 7.5.0.8588 and the CycloneDX Gradle plugin 3.5.1,
  and build-logic imports `jackson-bom` at the new catalog key `jackson2Tooling` (2.22.3). Their dependencies
  carried bcprov-jdk18on 1.84 (GHSA-9pwp-9qqc-pr26 CRITICAL, GHSA-qp49-qgx5-5m26) and Jackson 2.20.1 with
  fifteen advisories onto every Gradle build that applies the plugins; Sonar 7.5 ships its scanner shaded with
  bcprov 1.85.2. Applications are unaffected: their Jackson 2 stays at `jackson2Bom`.
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
  lockfiles and verification metadata these versions change. The bumps fix Tomcat CVE-2026-65905, CVE-2026-65182
  and CVE-2026-68525 (all CRITICAL); jackson-core CVE-2026-89425 and CVE-2026-89407 and jackson-databind
  CVE-2026-91777, CVE-2026-83557, CVE-2026-68497, CVE-2026-19032 and CVE-2026-91776, in Jackson 3 and 2 alike;
  jsoup CVE-2026-75140; and js-yaml CVE-2026-84375 (ids from OSV, 2026-10-20).
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

- Every check task of the conventions declares an output (`platformPinCheck`, `platformRuntimeImageCheck`,
  `platformCoverageDataCheck`, `platformBomOverrideCheck`), so an unchanged second build runs none of them
  again; a TestKit case holds that (N-REL-15). Only `platformQuarantineCheck` runs every time.
- `docs/http-client-and-agent-budget.md` is now `docs/api-client.md`; the agent half moved to
  `docs/agent-profile.md`.

- `SECURITY.md` names the support policy and the exact workflow pins instead of `@v1`.
- The frontend canon moves `vitest` and `@vitest/coverage-v8` from 4.1.10 to 4.1.11, which fixes
  GHSA-82fw-gwwq-j7x9 (path traversal through a redirected mock in `@vitest/mocker`); `platform-bump`
  applies it.
- The release-migration fixtures of `runtime-image-27` store their images as `docker-image.fixture`;
  `test/migrations.test.sh` restores the `Dockerfile` name in its copy. OpenSSF Scorecard counted them as
  unpinned images of Platform's own build.

### Fixed

- `AbstractFlywayMigrationTest` no longer overflows the stack on a migration whose version has many segments:
  both name patterns match the repeated `[._]<digits>` segment possessively, which accepts the same names
  (SonarQube java:S5998). The other SonarQube findings in `platform-test-fixtures` are fixed without changing
  behavior: the inherited tests declare the exceptions they throw instead of `Exception`
  (`AbstractFlywayMigrationTest.migrationsExistAndAreWellNamed()` throws `IOException` and `URISyntaxException`,
  `AbstractLiquibaseChangelogTest.masterChangelogExists()` nothing, `changesFollowTheDeployNaming()`
  `IOException`), `AbstractSchemaValidationIT.migrationsMatchTheEntities` takes the `Environment` as an
  `@Autowired` parameter instead of a private field, and `PlatformPostgresContainer` is
  `@Deprecated(since = "1.6.0")`. A subclass that overrides one of those test methods with the old signature
  no longer compiles; no consumer does (none).
- The SonarQube findings in `platform-security-starter` are fixed without changing behavior:
  `PlatformSecurityAutoConfiguration.platformSecurityFilterChain` no longer declares `throws Exception`, which
  Spring Security 7 no longer throws from the `HttpSecurity` DSL or `build()`, and assembles the chain in one
  private method per concern (CORS, CSRF, authorization, authentication) instead of one method above the
  cognitive-complexity limit (java:S3776, java:S112). The opt-in `platform.security.csrf=off` stays and is
  suppressed for java:S4502 on that one method. A subclass that overrides `platformSecurityFilterChain` with
  `throws Exception` no longer compiles; no consumer does (none).
- The `example` job of `release.yml` gives the npm step `GITHUB_TOKEN`, the variable that the rendered
  `frontend/.npmrc` (from `templates/npmrc`) reads, taken from the workflow's own token with `packages: read`.
  The job only set `NODE_AUTH_TOKEN`, which feeds the file `actions/setup-node` writes, and npm takes the token
  from the project's `.npmrc` instead, so it would have sent the literal `${GITHUB_TOKEN}` and got a 401 on the
  first real release. `PLATFORM_EXAMPLE_TOKEN` leaves the job's environment: a first step turns its presence
  into an output for the job's conditions, and only the step that clones and pushes `platform-example` gets it.
  `templates/tests/release-example-npm-auth.test.sh` asks npm offline which file wins and checks the step's
  environment. No consumer is affected (none).
- `backend-ci-smoke` in Platform's own `ci.yml` builds the `java-library` starter on the previous release when
  the commit is a release commit. `release.sh` moves the starter pin to the new version, which `release.yml`
  publishes only after `ci.yml` passes on that commit, so the smoke could not resolve the Platform plugins and
  would have blocked the release; the push of the same commit to `main` failed the same way. The new
  `smoke-platform-version` job passes the parent commit's pin when the commit changes it, and the commit's own pin
  otherwise.
- `canon-cve-scan.yml` scans the versions consumers get again. Since the conventions import `platform-bom`,
  `gradle/canon-probe` could not resolve it (it is not on Maven Central), so its SBOM carried Spring Boot's
  Jackson 3.1.5 and a Micrometer that Boot's BOM did not manage instead of the catalog's floors, and Grype failed
  on advisories no consumer has. The workflow now publishes the scanned commit's `platform-bom` to Maven local,
  the probe declares it as a platform and recognises a BOM by its catalog alias, so `spring-boot-bom` (the
  artifact `spring-boot-dependencies`) applies too, and `scripts/check-canon-floors.py` fails the scan when a
  Jackson or Tomcat component is below its catalog floor.
- `scorecard.yml` pins `ossf/scorecard-action` v2.4.3 by its commit, `4eaacf0`, instead of the SHA of its
  annotated tag, `99c09fe`. The runner resolved the tag, but publishing the result failed with "imposter
  commit … does not belong to ossf/scorecard-action". Platform's own `ci.yml` and `release.yml` pinned
  `pnpm/action-setup` v6.0.9 the same way and now pin its commit, `0ebf471`. `ci.yml` gains an
  `action-pins` job: `scripts/check-action-pins.sh` fails when a pinned SHA is not the commit its
  `# vX.Y.Z` comment points at.
- `merge.sh` treats `.kotlin/`, the cache the Kotlin Gradle plugin leaves in every module that compiles Kotlin
  (`gradle/build-logic`, a consumer's `buildSrc`), as regenerable build output. A worktree whose only leftover is
  that cache merges, and the cache goes with the worktree; before, the merge stopped with "has local or ignored
  files". A look-alike such as an ignored `.kotlin-notes` file still blocks.
- `seniordev.settings-conventions` counts an empty or whitespace-only `gpr.user`, `gpr.key`, `GITHUB_ACTOR` or
  `GITHUB_TOKEN` as unset, as the starters' preflight does (N-DX-18). A blank `gpr.key=` in `gradle.properties` no
  longer hides `GITHUB_TOKEN` from the GitHub Packages repository the plugin adds, where the catalog request then
  failed with a 401, and an empty variable sends no credentials instead of empty ones. The fix arrives with the
  bump; a backend's own `pluginManagement` block reads them the old way until it takes the starters' block (see
  Consumer action required).
- `extractCheckstyleConfig` and `extractSpotbugsConfig` no longer capture the plugin script object in
  their actions, which the configuration cache cannot serialize; a consumer that turns the cache on
  no longer fails `check` on them.
- Roadmap toolkit: auto-unblock reads the older marker layout, takes the status from the
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
- Platform's frontend lockfile takes the fixed releases of hono, undici, fast-uri, ip-address,
  brace-expansion, proxy-addr, qs, body-parser, `@modelcontextprotocol/sdk`, `@hono/node-server`, browserslist,
  postcss-selector-parser, source-map-js and baseline-browser-mapping. All of them are dev tooling (shadcn's MCP
  server, jsdom, ESLint, Next); no manifest changed. braces 3.0.3 has no fixed release and is accepted in
  `frontend/osv-scanner.toml` until 2027-01-19.
- `@dominiksienkiewicz/vitest-config` ships `index.d.ts` (a `types` field and a `types` export condition), typing
  `baseConfig` with Vitest's own `ViteUserConfig`. Without declarations a consumer's `vitest.config.ts` failed
  `tsc --noEmit` and `next build` with TS7016 under the canon's strict options, because `tsc` does not read
  `.js` files in `node_modules`. `test/consumer-types.test.mjs` unpacks the published tarball into a consumer
  fixture and type-checks the `vitest.config.ts` that `new-consumer.sh --frontend next` renders. No consumer
  action: the fix arrives with the bump.
- The `sonar` job of Platform's own `ci.yml` waits for SonarQube Cloud to process the analysis
  (`-Dsonar.qualitygate.wait=true`) and fails when the analysis is rejected or the quality gate is red. The
  first analyses of `platform-test-fixtures` and `platform-security-starter` left the job green and both
  dashboards empty: CI analyses `main`, the hand-made projects' main branch was `master`, and the Free plan
  analyses only the main branch and pull requests of a private project. RELEASING.md and ADR-0012 add renaming the main branch to `main` to the
  one-time setup, and `templates/tests/ci-sonar.test.sh` checks the job's flag. No consumer is affected (none).
- The `sonar` job of Platform's own `ci.yml` analyses every module before it fails, naming each module whose
  analysis failed; before, a red `platform-test-fixtures` ended the step, so `platform-security-starter` was never
  analysed. `templates/tests/ci-sonar-modules.test.sh` runs the loop on stub Gradle wrappers. The one-time setup in
  RELEASING.md and ADR-0012 adds the two steps the waiting job exposed: both projects are public, because the
  Free plan caps the organisation's private code at 50k lines and Azimuth fills it, and each has a New code
  definition, without which the quality gate is not computed. No consumer is affected (none).

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
