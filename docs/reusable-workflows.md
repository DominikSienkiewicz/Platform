# Reusable workflows: the caller contract

Platform ships 10 reusable workflows. This page lists what a caller must provide to each: the
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
  when the contract changes without updating its snapshot.

## backend-ci.yml

Builds a Gradle backend on the JDK 27 toolchain and runs `gradle-task` (default `build`).

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

## frontend-ci.yml

Installs with `npm ci`, runs the version guard, lint, typecheck, test and build, and optionally the
Playwright tests, whose report and traces it uploads as the artifact `playwright-report-<run id>`. With
`strict: true` the guard and the scripts `lint`, `typecheck`, `test`, `build` and `format:check` are
required, and `format:check` runs before lint.

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

## semgrep.yml

Static analysis of the source code. ERROR findings fail the run; accepting one is described in
[security-scanning.md](security-scanning.md). Platform runs the default rulesets on itself from
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

## sonar.yml

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

## platform-bump.yml

Bumps the repository to a Platform release and opens a pull request with the diff: the Gradle and npm
pins, the frontend canon, the reusable workflow references, the lockfiles and the dependency
verification metadata. Schedule it in the caller; it runs the newest published `platform-bump` bin, so
it also works in a repository without a frontend.

- Permissions: `contents: write`, `pull-requests: write`, `packages: read`. Platform's commands run in a
  job that can only read; a second job applies the diff, pushes `platform-bump/v<version>` and opens the
  pull request. A branch that already exists is left alone.
- Secret `gpr_token` (optional): a classic PAT with `read:packages`, as for backend-ci.
- Secret `bump_token` (optional): a classic PAT with the `repo` and `workflow` scopes. A pull request
  opened with the automatic `GITHUB_TOKEN` runs no CI, and that token may not push workflow changes, so
  without `bump_token` the workflow references stay and the pull request says so. The fallback also needs
  **Allow GitHub Actions to create and approve pull requests** in the repository's Actions settings.
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
