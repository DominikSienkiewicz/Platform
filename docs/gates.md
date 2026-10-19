# Gate codes

Every Platform gate names its failure with a stable code, and the message links the anchor below in the
docs of the release that produced it (`/blob/v<version>/docs/gates.md#<code>`), so an agent or a reviewer
reads the rules that release enforces, not those of `main`. A code keeps its meaning forever; a retired code
is never reused. `templates/tests/gate-codes.test.sh` fails when a code in the sources has no section here,
or a section names a code nothing emits.

To see which gate costs consumers the most, collect the annotations of their failed runs locally (the
consumers are private, so this never runs in Platform's CI) and count them per code, week and pin:

```bash
gh api "repos/<owner>/<repo>/check-runs/<check-run id>/annotations" \
  --jq '[.[] | {repo: "<owner>/<repo>", pin: "<pin>", completed_at: "<date>", title, message}]' > annotations.json
```

```bash
python3 scripts/gate-failures.py annotations.json
```

The table holds counts only, never the messages.

To escalate any of them, open an issue in DominikSienkiewicz/Platform with the code, the full message and
the Platform version from the link.

## Gradle

### PLAT-DEP-001

**Cause:** an explicit version of a library that is not in the Platform catalog, and no Platform BOM manages
it (`platformDependencyCheck`).
**Example:** `implementation("com.example:unknown:1.0")`.
**Fix:** add the library to `gradle/catalog/libs.versions.toml` in Platform, release, bump the pin, then
declare it as `libs.<alias>` ([versions.md](versions.md)).

### PLAT-DEP-002

**Cause:** an explicit version that differs from the Platform canon.
**Example:** `implementation("org.jsoup:jsoup:1.0.0")` while the canon has another version.
**Fix:** declare it through the alias the message names, which carries the canon version.

### PLAT-DEP-003

**Cause:** an explicit version of a library the Platform BOMs manage, either a catalog entry without a version
or a Spring starter.
**Example:** `implementation("org.springframework.boot:spring-boot-starter-webmvc:4.0.0")`.
**Fix:** remove the version. To run another version on purpose, override the BOM property instead;
`platformBomOverrideCheck` reports it as a warning (Decision 18).

### PLAT-DEP-004

**Cause:** the `libs` catalog of the consumer overrides a version of the Platform canon with `version(...)`
after `from(...)` in `settings.gradle.kts`. The check compares with the canon embedded in the plugin, so the
override cannot redefine what is canonical.
**Example:** `version("jsoup", "1.0.0")` inside `create("libs") { from("pl.seniordeveloper:platform-catalog:…") }`.
**Fix:** remove the override; a different version needs a Platform release.

### PLAT-DEP-005

**Cause:** a project that applies `seniordev.java-conventions` has no version catalog named `libs`.
**Example:** `create("platformLibs") { from("pl.seniordeveloper:platform-catalog:…") }`.
**Fix:** name the catalog `libs`, as [consuming.md](consuming.md#backend) shows.

### PLAT-PIN-001

**Cause:** the settings plugin and `platform-catalog` are pinned to different releases (`platformPinCheck`).
**Fix:** run `scripts/platform-bump.sh <version>`, or read both pins from `platformVersion`.

### PLAT-IMG-001

**Cause:** the final `FROM` of the Dockerfile runs an older Java than the toolchain of the bytecode
(`platformRuntimeImageCheck`).
**Fix:** use the final `FROM` of [`templates/Dockerfile.backend`](../templates/Dockerfile.backend).

### PLAT-COV-001

**Cause:** `coverageMinimum` is above 0, but no test task produced JaCoCo execution data
(`platformCoverageDataCheck`).
**Fix:** add tests to the module, or set `coverageMinimum=0` for it.

### PLAT-COV-002

**Cause:** `coverageMinimum` is not a decimal between 0 and 1.
**Example:** `coverageMinimum=80` or `coverageMinimum=0,8`.
**Fix:** write a fraction, such as `coverageMinimum=0.80`.

### PLAT-COV-003

**Cause:** the coverage of `test` and `integrationTest` together is below `coverageMinimum`
(`jacocoTestCoverageVerification`; `backend-ci.yml` names the code).
**Fix:** cover the code the report lists, or lower the threshold in a reviewed change.

### PLAT-VER-001

**Cause:** Gradle dependency verification rejected an artifact without a checksum in
`gradle/verification-metadata.xml` (`backend-ci.yml` names the code).
**Fix:** run `scripts/platform-bump.sh` again, or regenerate the metadata in two passes as
[versions.md](versions.md#dependency-verification) describes.

## Frontend

### PLAT-FE-001

**Cause:** a dependency without an entry in the frontend canon (`platform-versions-check`).
**Fix:** add it to `frontend/packages/versions/versions.json` in Platform, release, then bump.

### PLAT-FE-002

**Cause:** a dependency or an `overrides` entry declared at a version other than the canon's.
**Fix:** `npx platform-versions-check --fix` rewrites it offline; then `npm install --package-lock-only`.

### PLAT-FE-003

**Cause:** the `@dominiksienkiewicz/*` packages are not all pinned at one exact version, the release of the
installed `@dominiksienkiewicz/versions`.
**Fix:** `npx platform-versions-check --fix`, or `scripts/platform-bump.sh <version>`.

## CI

### PLAT-CI-001

**Cause:** strict `frontend-ci.yml` is missing something it requires: `@dominiksienkiewicz/versions`, one of
the scripts `lint`, `typecheck`, `test`, `build` and `format:check`, or `@dominiksienkiewicz/openapi` when
`package.json` configures `platform.openapi`.
**Fix:** add what the annotation names ([reusable-workflows.md](reusable-workflows.md#frontend-ciyml)).

### PLAT-SAST-001

**Cause:** Semgrep found findings of severity ERROR (`semgrep.yml`).
**Fix:** fix them, or record an exception as [security-scanning.md](security-scanning.md) describes.

### PLAT-SCA-001

**Cause:** Grype found vulnerabilities at or above the severity cutoff in the SBOM, the frontend lockfile or
an image (`security-scan.yml`, `container-scan.yml`).
**Fix:** move to a fixed version; accept a finding without a fix only through `.grype.yaml`
([security-scanning.md](security-scanning.md)).

## Deprecations

### PLAT-DEPR-001

**Cause:** something Platform deprecates is still in use: a dependency, a Gradle property or a plugin
(`platformDependencyCheck`, from the plugin's `platform-deprecations.tsv`), a frontend package (the
`deprecated` map of `versions.json`), or a deprecated workflow or input. It warns and keeps working;
`-Pplatform.deprecations=fail` makes the Gradle side fail, as Platform's own TestKit suite does.
**Fix:** use the replacement the message names before the release it names. Platform deprecates in one
MINOR and removes no earlier than the next, and the CHANGELOG lists both.
