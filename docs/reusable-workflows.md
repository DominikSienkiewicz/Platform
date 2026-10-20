# Reusable workflows: the caller contract

Platform ships 11 reusable workflows. This page lists what a caller must provide to each: the
`permissions` it grants, the secrets and variables it passes, and a snippet to copy. Inputs, their
types and defaults are described in the workflow files themselves (every input has a
`description:`); this page links to them instead of repeating them.

## Rules that apply to every workflow

- **Reference an exact tag.** Use the tag of your Platform pin, for example
  `uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.6.0`
  ([ADR-0002](adr/0002-release-and-versioning-contract.md), item 6). `platform-bump` moves it together
  with the pins, `@v1` included. The moving `@v1` still works but changes under you on every
  Platform release.
- **Grant the permissions listed below.** A called workflow can never get more than its caller
  grants, so a missing permission ends the run with `startup_failure` before any step runs.
- **Pass secrets explicitly** where a workflow declares them, as in the snippets below. Avoid
  `secrets: inherit`: it hands every repository secret to Platform code.
- **Every job has a time limit.** A calling job cannot set `timeout-minutes` on a `uses:` job, so
  each workflow takes it as an input: `timeout-minutes` (in `deploy.yml`, `build-timeout-minutes` and
  `deploy-timeout-minutes`), with a default of a few times the longest measured run. Pass a larger
  value with `with:` when your build is slower; GitHub's own default is 360 minutes.
- **Contract changes are announced.** A new permission, input, secret or changed default is a
  consumer action: it ships in a MINOR release with a **Consumer action required** entry in
  [CHANGELOG.md](../CHANGELOG.md). `templates/tests/workflow-contract.test.sh` fails Platform's CI
  when the contract changes without updating its snapshot; copy the snapshot to
  `frontend/packages/versions/workflow-contract.txt` too, which `platform-workflows-check` reads.
- **Check your callers.** `npx platform-workflows-check` (from `frontend/`, with
  `@dominiksienkiewicz/versions` installed) holds every caller in `.github/workflows/` to this
  contract: permissions, inputs, required inputs and secrets. `platform-bump` runs it against the
  release it moves to.

## backend-ci.yml

Builds a Gradle backend on the JDK 27 toolchain and runs `gradle-task` (default `build`). With
`lint-task: lint` it first runs the formatter and linters of `seniordev.java-conventions` as a separate
step, so a style failure arrives before the tests run. The test,
test-result and Checkstyle reports of every module go into the `backend-test-reports-<run id>` artifact
(seven days). When the job fails, it annotates each failed test and Checkstyle violation at its file
and line (ten at most), and the job summary lists all of them with Gradle's "What went wrong".
The Gradle step sets `PLATFORM_TEST_RETRY=detect`: a failing test runs once more, a test that passes only
then still fails the build, and a "Test health" summary lists the flaky tests, the `quarantineTest` result
when the caller runs it, and every quarantine deadline (`-Pplatform.test.retry=off` in `gradle-task` turns
the retry off). With `verify-provenance: true` the job checks the artifact attestation of every Platform
jar the build resolved against Platform's `release.yml` and fails with
[PLAT-PROV-001](gates.md#plat-prov-001) on one without it; Platform attests its jars from 1.6.0 on.

- Permissions: `contents: read`, `packages: read`.
- Secret `gpr_token` (optional): a classic PAT with `read:packages`. Without it the caller's
  automatic `GITHUB_TOKEN` is used, which also needs access to Platform's packages.
- Inputs: [backend-ci.yml](../.github/workflows/backend-ci.yml).

```yaml
permissions:
  contents: read
  packages: read
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@vX.Y.Z
    with:
      working-directory: backend # "." for the templates/jvm layout
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs backend-ci.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `30` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
| `working-directory` | string | `backend` | Directory of the Gradle build, relative to the repository root (`.` for the templates/jvm layout). |
| `java-version` | string | `25` | JDK that runs Gradle. Platform's build-logic is compiled for Java 25, so Gradle must run on 25 or newer. |
| `toolchain-java-version` | string | `27` | Toolchain JDK that seniordev.java-conventions compiles with; installed by setup-java, not Foojay. |
| `gradle-task` | string | `build` | Gradle task arguments as one line, separated by whitespace; passed literally, without shell parsing. The step sets PLATFORM_TEST_RETRY=detect, so a flaky test is retried once and still fails the build; -Pplatform.test.retry=off here turns that off. |
| `verify-provenance` | boolean | `false` | Verify the artifact attestation of every Platform jar the build resolved (pl.seniordeveloper in the Gradle cache) against Platform's release.yml; Platform 1.6.0 and newer attest their jars. |
| `lint-task` | string | empty | Optional Gradle task arguments run as a first step before gradle-task, such as `lint` from seniordev.java-conventions, so style failures arrive before the tests; empty skips the step. |
| `red-proof` | boolean | `false` | On a pull_request event, run a red-proof job: every fix: commit of the pull request must add or change a test class, and those classes must fail against the production code (src/main) of the commit's parent. Needs the pull request's history, so the job checks out with full depth. |
| `red-proof-tasks` | string | `test` | Gradle test tasks the red-proof job runs, separated by whitespace, each with --tests for every test class of the fix: commit, such as `test integrationTest`. |
<!-- /docs-gen -->

### Red-proof

With `red-proof: true`, a pull request also runs the job `red-proof`, which proves that each `fix:` commit of the
pull request reproduces its bug ([fix a bug test-first](runbooks/tdd-bugfix.md)). The branch is green in every
commit, so the red of a regression test is visible only against the code it fixes. For each commit between the
pull request's base and head whose subject starts with `fix:` (`fix(scope):` and `fix!:` included), the job:

1. takes the test classes the commit added or changed: source files under `src/<set>/{java,kotlin,groovy}/` of
   any source set but `main`, named `…Test`, `…Tests`, `…IT`, `…ITCase` or `…Spec`, the class name read from the
   path;
2. checks out the commit, then puts every `src/main/` file the commit changed back to its parent's version (a file
   the commit added is removed);
3. runs each task of `red-proof-tasks` (default `test`) with `--tests <class>` for each of those classes, with
   `--continue` and `-Pplatform.test.retry=off`;
4. reads the JUnit XML reports of those classes: at least one must report a failure or an error.

It fails with [PLAT-RED-001](gates.md#plat-red-001) on a `fix:` commit without a test class,
[PLAT-RED-002](gates.md#plat-red-002) when its tests pass on the parent and
[PLAT-RED-003](gates.md#plat-red-003) when none of them ran there, for example because the test does not
compile against the parent. The job summary lists each class with its result on the parent. Commits of other
types, and runs on events other than `pull_request`, are skipped.

Caller contract: no permission and no secret beyond the `build` job's; the job checks out the pull request's head
with full history. A unit test that fails in a fresh JVM for an unrelated reason counts as red, so keep the suite
green. Name the task of each source set the fix commits touch, such as `red-proof-tasks: test integrationTest`.

```yaml
jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@vX.Y.Z
    with:
      red-proof: true
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
```

## frontend-ci.yml

Installs with `npm ci`, runs the version guard, lint, typecheck, test and build, and optionally the
Playwright tests, whose report and traces it uploads as the artifact `playwright-report-<run id>`. With
`strict: true` the guard and the scripts `lint`, `typecheck`, `test`, `build` and `format:check` are
required, and `format:check` runs before lint. When lint, typecheck, test or build fails, an
annotation and the job summary name that script. A strict caller whose `package.json` configures
`platform.openapi` also gets `platform-openapi-check` ([api-contracts.md](api-contracts.md)).

- Permissions: `contents: read`, `packages: read`.
- Secret `gpr_token` (optional): a token that can read `@dominiksienkiewicz/*` from GitHub Packages.
  Without it the caller's automatic `GITHUB_TOKEN` is used, which also needs access to Platform's
  packages.
- Inputs: [frontend-ci.yml](../.github/workflows/frontend-ci.yml).

```yaml
permissions:
  contents: read
  packages: read
jobs:
  frontend:
    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@vX.Y.Z
    with:
      strict: true
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs frontend-ci.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `20` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
| `working-directory` | string | `frontend` | Directory of the frontend package.json, relative to the repository root. |
| `node-version` | string | `24` | Node.js version for install, lint, test and build. |
| `strict` | boolean | `false` | Require the Platform guard and the lint, typecheck, test, build and format:check scripts, run format:check, and check the OpenAPI types when package.json configures platform.openapi. |
| `run-e2e` | boolean | `false` | Run the Playwright end-to-end tests (`npm run test:e2e`) after the build. |
<!-- /docs-gen -->

## api-contract.yml

Fails a pull request that breaks the committed OpenAPI spec for existing clients: oasdiff compares the
spec at the pull request's base with the one in the pull request and writes its changelog to the job
summary. A pull request labelled `allow-label` (default `api-breaking`) passes with a warning. The
`breaking` output is `true` when oasdiff found a change at or above `fail-on`. See
[api-contracts.md](api-contracts.md).

- Permissions: `contents: read`.
- No secrets.
- Trigger on `pull_request` with the `labeled` and `unlabeled` types, so adding the label re-runs the
  gate. The job runs oasdiff from a digest-pinned image, without network access.
- Inputs: [api-contract.yml](../.github/workflows/api-contract.yml).

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]
permissions:
  contents: read
jobs:
  api-contract:
    uses: DominikSienkiewicz/Platform/.github/workflows/api-contract.yml@vX.Y.Z
    with:
      spec-path: contract/openapi.yaml
```

Inputs:

<!-- docs-gen:inputs api-contract.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `spec-path` | string | required | Path of the committed OpenAPI spec (YAML or JSON), relative to the repository root. |
| `base-spec-path` | string | empty | Compare against this file of the checked-out revision instead of spec-path at the pull request's base; Platform's self-test uses it. |
| `fail-on` | string | `ERR` | Lowest oasdiff level that counts as breaking: ERR, WARN or INFO. |
| `allow-label` | string | `api-breaking` | Pull request label that lets a breaking change through; say why in the pull request description. |
| `fail-on-breaking` | boolean | `true` | Fail the job on a breaking change; false only reports it in the breaking output. |
| `oasdiff-image` | string | `tufin/oasdiff:v1.33.0@sha256:6263a96dd2ef0726c54e21fea9b8e1607eac4841add0079324b424c1f52b819c` | oasdiff container image, pinned by digest. |
| `timeout-minutes` | number | `10` | Minutes before the job is cancelled; GitHub's default is 360. |
<!-- /docs-gen -->

## security-scan.yml

Scans dependencies for CVEs: the backend through its CycloneDX SBOM, the frontend through
`package-lock.json`, both with Grype. CRITICAL and HIGH fail the run.

- Permissions: `contents: read`, plus `packages: read` when the backend resolves Platform artifacts.
- Secret `gpr_token` (optional), as for backend-ci.
- Inputs: [security-scan.yml](../.github/workflows/security-scan.yml). With `only-if-deps-changed: true`
  a push or pull request scans only when a changed path matches `deps-pattern` (the Gradle build and
  lock files, `verification-metadata.xml`, `frontend/package*.json` and the workflow files by
  default); scheduled and manual runs always scan. It replaces the `changes` job callers copied.

```yaml
permissions:
  contents: read
  packages: read
jobs:
  scan:
    uses: DominikSienkiewicz/Platform/.github/workflows/security-scan.yml@vX.Y.Z
    with:
      only-if-deps-changed: true
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs security-scan.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `15` | Minutes before each job is cancelled; GitHub's default is 360. Raise it for a slower build. |
| `working-directory` | string | `backend` | Directory of the Gradle build, relative to the repository root. |
| `java-version` | string | `25` | JDK that runs Gradle for the CycloneDX SBOM. |
| `severity-cutoff` | string | `high` | Grype fail threshold for the SBOM and the frontend lockfile: negligible, low, medium, high or critical. |
| `run-frontend` | boolean | `true` | Also scan frontend/package-lock.json. Use false for a backend without a frontend. |
| `only-if-deps-changed` | boolean | `false` | On push and pull_request, scan only when a changed path matches deps-pattern. Schedules and manual runs always scan. |
| `deps-pattern` | string | `^(backend/(build|settings)\.gradle\.kts|backend/(settings-)?gradle\.lockfile|backend/gradle/verification-metadata\.xml|backend/gradle/libs\.versions\.toml|frontend/package(-lock)?\.json|\.github/workflows/[^/]+\.ya?ml)$` | Extended regular expression matched against every changed path when only-if-deps-changed is on. |
| `only-fixed` | boolean | `false` | Fail only on vulnerabilities that have a fix. Accept a finding without a fix through .grype.yaml instead; see docs/security-scanning.md. |
<!-- /docs-gen -->

## container-scan.yml

Re-scans published images, usually on a schedule. Grype is the gate; Snyk is advisory.

- Permissions: `contents: read`, `packages: read` (to pull private images from GHCR).
- Secret `snyk_token` (optional): without it the Snyk steps are skipped.
- Inputs: [container-scan.yml](../.github/workflows/container-scan.yml); `images` is required.

```yaml
permissions:
  contents: read
  packages: read
jobs:
  container-scan:
    uses: DominikSienkiewicz/Platform/.github/workflows/container-scan.yml@vX.Y.Z
    with:
      images: '["ghcr.io/owner/app-backend:latest"]'
    secrets:
      snyk_token: ${{ secrets.SNYK_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs container-scan.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `15` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
| `images` | string | required | JSON array of full image references to scan, e.g. '["ghcr.io/owner/app:latest"]'. |
| `severity-cutoff` | string | `high` | Grype fail threshold: negligible, low, medium, high or critical. |
| `only-fixed` | boolean | `true` | Fail only on vulnerabilities that have a fix. Base images carry unfixable HIGH OS CVEs, which would otherwise keep the gate red. |
<!-- /docs-gen -->

## semgrep.yml

Static analysis of the source code. CRITICAL, HIGH and ERROR findings fail the run, and the log counts every
severity; accepting a finding is described in [security-scanning.md](security-scanning.md). Platform runs the
default rulesets on itself from
`self-scan.yml`, pull requests included.

- Permissions: `contents: read`.
- No secrets.
- Inputs: [semgrep.yml](../.github/workflows/semgrep.yml).

```yaml
permissions:
  contents: read
jobs:
  semgrep:
    uses: DominikSienkiewicz/Platform/.github/workflows/semgrep.yml@vX.Y.Z
```

Inputs:

<!-- docs-gen:inputs semgrep.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `10` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
| `config` | string | `p/default p/secrets p/java p/javascript p/typescript p/dockerfile p/github-actions` | Semgrep rulesets, separated by spaces; each gets its own --config. |
| `semgrep-version` | string | `1.168.0` | Pinned Semgrep CLI version, installed with pipx. |
<!-- /docs-gen -->

## scorecard.yml

OpenSSF Scorecard. It only makes sense in a public repository; private callers usually skip it
with `if: ${{ !github.event.repository.private }}`. Platform runs it on itself from
[`self-scan.yml`](../.github/workflows/self-scan.yml) on every push to `main` and weekly, and
publishes the result.

- Permissions on the calling job: `contents: read`, `security-events: write`, `id-token: write`.
- No secrets and no inputs.

```yaml
jobs:
  scorecard:
    if: ${{ !github.event.repository.private }}
    permissions:
      contents: read
      security-events: write
      id-token: write
    uses: DominikSienkiewicz/Platform/.github/workflows/scorecard.yml@vX.Y.Z
```

Inputs:

<!-- docs-gen:inputs scorecard.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `10` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
<!-- /docs-gen -->

## sonar.yml

**Deprecated.** No consumer calls this workflow: two removed their Sonar jobs on 2026-08-05, and
the third scans inline, within SonarQube Cloud's 50,000-line limit for private projects. It stays so
that existing references resolve; do not adopt it. Run the `sonar` task in the backend job instead,
which `seniordev.quality-conventions` configures.

SonarQube Cloud for a backend plus frontend monorepo. Both jobs are skipped until the repository has
a `SONAR_TOKEN` secret.

- Permissions: `contents: read`, `packages: read`.
- Secrets `SONAR_TOKEN` and `gpr_token`, both optional: without `SONAR_TOKEN` both jobs are skipped,
  without `gpr_token` the automatic `GITHUB_TOKEN` resolves Platform's packages.
- Inputs: [sonar.yml](../.github/workflows/sonar.yml).

```yaml
permissions:
  contents: read
  packages: read
jobs:
  sonar:
    uses: DominikSienkiewicz/Platform/.github/workflows/sonar.yml@vX.Y.Z
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      gpr_token: ${{ secrets.GPR_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs sonar.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `java-version` | string | `25` | JDK that runs Gradle for the backend scan. |
| `toolchain-java-version` | string | `27` | Toolchain JDK that seniordev.java-conventions compiles with; installed by setup-java, not Foojay. |
| `node-version` | string | `24` | Node.js version for the frontend tests and coverage. |
<!-- /docs-gen -->

## platform-bump.yml

Bumps the repository to a Platform release and opens a pull request with the diff: the Gradle and npm
pins, the frontend canon, the reusable workflow references, the lockfiles and the dependency
verification metadata. Schedule it in the caller; it starts the newest published `platform-bump` bin,
which hands over to the bin of the target release (from that release's assets, checked against its
`SHA256SUMS`), so the bump always runs the logic of the release it goes to, also in a repository without a
frontend. The pull request body opens with the impact report of `platform-bump --report`: what of the
crossed releases affects this repository, what it does not use, and what needs action.

- Permissions: `contents: write`, `pull-requests: write`, `packages: read`. Platform's commands run in a
  job that can only read; a second job applies the diff, pushes `platform-bump/v<version>` and opens the
  pull request. A branch that already exists is left alone.
- Secret `gpr_token` (optional): a classic PAT with `read:packages`, as for backend-ci.
- Secret `bump_token` (optional): a classic PAT with the `repo` and `workflow` scopes. A pull request
  opened with the automatic `GITHUB_TOKEN` runs no CI, and that token may not push workflow changes, so
  without `bump_token` the workflow references stay and the pull request says so. The fallback also needs
  **Allow GitHub Actions to create and approve pull requests** in the repository's Actions settings.
  `scripts/repo-settings.sh --check --consumers`, run by the Platform maintainer, reports both for every
  repository in `scripts/consumers.txt`, and `--apply --consumers` turns the setting on.
- Inputs: [platform-bump.yml](../.github/workflows/platform-bump.yml); `version` empty takes the newest
  release of the current MAJOR.

```yaml
on:
  schedule:
    - cron: "0 6 * * 1"
  workflow_dispatch:
    inputs:
      version:
        type: string
        default: ""
permissions:
  contents: write
  pull-requests: write
  packages: read
jobs:
  bump:
    uses: DominikSienkiewicz/Platform/.github/workflows/platform-bump.yml@vX.Y.Z
    with:
      version: ${{ inputs.version || '' }}
    secrets:
      gpr_token: ${{ secrets.GPR_TOKEN }}
      bump_token: ${{ secrets.PLATFORM_BUMP_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs platform-bump.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `30` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
| `version` | string | empty | Platform version to bump to; empty takes the newest release of the current MAJOR. |
| `java-version` | string | `25` | JDK that runs Gradle for the lockfile regeneration. Platform's build-logic is compiled for Java 25. |
| `toolchain-java-version` | string | `27` | Toolchain JDK that seniordev.java-conventions compiles with; installed by setup-java, not Foojay. |
| `node-version` | string | `24` | Node.js version that runs the platform-bump bin and npm. |
<!-- /docs-gen -->

## roadmap-unblock.yml

Moves dependent roadmap items to ready when their prerequisite issues are closed. The caller's
repository provides `scripts/roadmap-unblock.sh`.

- Permissions: `contents: read`.
- Secret `ROADMAP_PROJECT_TOKEN` (optional): Projects v2 of a user account accept only a classic PAT
  with the `project` and `repo` scopes. `repo` grants write access to every private repository of the
  owner, so give the token 90 days at most. A fine-grained PAT is not verified for user-owned
  Projects v2. Without the token the job warns and does nothing.
- Variable `ROADMAP_PROJECT_NUMBER`: the number of the Projects v2 board.

```yaml
on:
  issues:
    types: [closed]
permissions:
  contents: read
jobs:
  unblock:
    uses: DominikSienkiewicz/Platform/.github/workflows/roadmap-unblock.yml@vX.Y.Z
    secrets:
      ROADMAP_PROJECT_TOKEN: ${{ secrets.ROADMAP_PROJECT_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs roadmap-unblock.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `timeout-minutes` | number | `5` | Minutes before the job is cancelled; GitHub's default is 360. Raise it for a slower build. |
<!-- /docs-gen -->

## deploy.yml

Builds, scans (optionally), pushes and deploys the application images to a host over SSH. With
`scan-images: true`, Grype gates the deploy; Snyk runs in a separate advisory job with read-only
package access, which the deploy does not wait for.

- Permissions: `contents: read`, `packages: write` (to push to GHCR).
- Secrets: `GPR_USER`, `GPR_KEY`, `NPM_GH_TOKEN` and optionally `SNYK_TOKEN`, passed by the caller.
  They are declared optional so that the `preflight` job, not GitHub, names the missing ones.
- Environment `production`: the `deploy` job runs in it. Its deployment branch policy admits only
  `release`, and `SSH_HOST`, `SSH_USER`, `SSH_KEY` and `SSH_KNOWN_HOSTS` are secrets of that
  environment, so a workflow on any other branch can neither deploy nor read the SSH key. The job
  checks them in its first step. GitHub offers required reviewers for private repositories only on
  Enterprise, so the branch policy is the gate. Environment secrets in a private repository need
  GitHub Pro, Team or Enterprise.
- Set all of it with `templates/setup-gh-deploy.sh` from `templates/secrets.local.example`: it creates
  the environment and its `release` policy, stores the SSH secrets there, and names the
  repository-level `SSH_*` secrets an older bootstrap left, with the commands that delete them. Give it
  `SSH_HOST_KEY_SHA256` from a trusted channel, and it refuses a scanned host key with another
  fingerprint instead of trusting it on first use.
- Variables: `GHCR_OWNER`, `DEPLOY_PATH`.
- Inputs: [deploy.yml](../.github/workflows/deploy.yml); `app-name` is required. Set `platform-ref`
  to the tag in `uses:`, so that `scripts/deploy-remote.sh` comes from the same release as the
  workflow; its default `v1` is transitional.
- Rollback dispatch: `rollback-to-backend` and `rollback-to-frontend` take a tag that is already in GHCR.
  Either one skips `build-push`, the `versions` job checks that the tags exist, and the deploy runs the
  given tag; an empty one keeps the version of the checkout. Wire them to `workflow_dispatch` inputs of
  the caller. The migrate tag follows the backend, so a rollback runs the older changelog, which finds
  nothing pending.
- Rollback on the host: `scripts/deploy-remote.sh` writes the running tags to `.env.deploy.previous`
  before it replaces a layer. When the new backend, or a frontend whose compose service defines a
  healthcheck, does not become healthy within two minutes, it recreates that layer with the previous
  tag from the local image and the job fails with `ROLLED BACK to <tag>`. Database migrations are never
  rolled back, so every schema change must be expand/contract: the previous release must still run on
  the new schema. A first deploy has nothing to roll back to and fails as before.

```yaml
permissions:
  contents: read
  packages: write
jobs:
  deploy:
    uses: DominikSienkiewicz/Platform/.github/workflows/deploy.yml@vX.Y.Z
    with:
      app-name: myapp
      platform-ref: vX.Y.Z
    secrets:
      GPR_USER: ${{ secrets.GPR_USER }}
      GPR_KEY: ${{ secrets.GPR_KEY }}
      NPM_GH_TOKEN: ${{ secrets.NPM_GH_TOKEN }}
      SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
```

Inputs:

<!-- docs-gen:inputs deploy.yml -->
| Input | Type | Default | Description |
|---|---|---|---|
| `build-timeout-minutes` | number | `30` | Minutes before the build-push job is cancelled; GitHub's default is 360. |
| `deploy-timeout-minutes` | number | `20` | Minutes before the deploy job (upload, migrations, health gate) is cancelled; GitHub's default is 360. |
| `app-name` | string | required | Image name prefix, e.g. skillsprintplus or bookofstyling. |
| `compose-dir` | string | `.` | Directory with the compose file and the Caddyfile on the host (e.g. '.' or 'infra'). |
| `has-worker` | boolean | `false` | Also build the <app>-eval-worker image. |
| `migrate-image-suffix` | string | `migrate` | Suffix of the migration image (e.g. 'migrate' or 'db-migrate'). |
| `migrate-tag-source` | string | `backend` | Tag of the migration image: 'backend' (the backend version) or 'changelog' (the changelog number). |
| `java-version` | string | `25` | JDK that runs Gradle. Platform's build-logic is compiled for Java 25, so Gradle must run on 25 or newer. |
| `toolchain-java-version` | string | `27` | Toolchain JDK that seniordev.java-conventions compiles with; installed by setup-java, not Foojay. |
| `has-migrate` | boolean | `true` | Build and run a separate migration image. Use false for applications that migrate on start (Flyway). |
| `scan-images` | boolean | `false` | Scan the pushed images before deploying (Grype gate, optional Snyk). Opt-in. |
| `scan-severity` | string | `high` | Grype fail threshold for scan-images. |
| `compose-file` | string | `docker-compose.prod.yml` | Compose file name in compose-dir. |
| `base-env` | string | empty | Base env file on the host; empty picks .env.prod, then .env. |
| `platform-ref` | string | `v1` | Ref of DominikSienkiewicz/Platform that scripts/deploy-remote.sh is taken from; set it to the tag pinned in uses:. |
| `rollback-to-backend` | string | empty | Backend image tag already in GHCR to deploy again, for a rollback dispatch; empty deploys the version of the checkout. Either rollback input skips build-push. |
| `rollback-to-frontend` | string | empty | Frontend image tag already in GHCR to deploy again, for a rollback dispatch; empty deploys the version of the checkout. Either rollback input skips build-push. |
<!-- /docs-gen -->

