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
  (`sapmachine:27-jre`) before taking this release.
- Callers of `frontend-ci.yml` must grant `packages: read`. The workflow now requests it, so the
  automatic `GITHUB_TOKEN` fallback can read `@dominiksienkiewicz/*`, and a caller that grants only
  `contents: read` fails with `startup_failure`. Pass `gpr_token` explicitly as shown in
  `docs/reusable-workflows.md`.
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
- `platform-test-fixtures` and `platform-security-starter` publish a sources jar, and every
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
