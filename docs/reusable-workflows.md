# Reusable workflows: the caller contract

Platform ships 9 reusable workflows. This page lists what a caller must provide to each: the
`permissions` it grants, the secrets and variables it passes, and a snippet to copy. Inputs, their
types and defaults are described in the workflow files themselves (every input has a
`description:`); this page links to them instead of repeating them.

## Rules that apply to every workflow

- **Reference an exact tag.** Use the tag of your Platform pin, for example
  `uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.6.0`, and bump it together
  with the pin ([ADR-0002](adr/0002-release-and-versioning-contract.md), item 6). The moving `@v1`
  still works but changes under you on every Platform release.
- **Grant the permissions listed below.** A called workflow can never get more than its caller
  grants, so a missing permission ends the run with `startup_failure` before any step runs.
- **Pass secrets explicitly** where a workflow declares them, as in the snippets below. Avoid
  `secrets: inherit`: it hands every repository secret to Platform code.
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
Playwright tests. With `strict: true` the guard and the scripts `lint`, `typecheck`, `test` and
`build` are required.

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
- Inputs: [security-scan.yml](../.github/workflows/security-scan.yml).

```yaml
permissions:
  contents: read
  packages: read
jobs:
  scan:
    uses: DominikSienkiewicz/Platform/.github/workflows/security-scan.yml@vX.Y.Z
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
- Secrets: `GPR_USER`, `GPR_KEY`, `NPM_GH_TOKEN`, `SSH_HOST`, `SSH_USER`, `SSH_KEY`,
  `SSH_KNOWN_HOSTS`, optionally `SNYK_TOKEN`. They are declared optional so that the `preflight` job,
  not GitHub, names the missing ones. Set them with `templates/setup-gh-deploy.sh` from
  `templates/secrets.local.example`; give it `SSH_HOST_KEY_SHA256` from a trusted channel, and it
  refuses a scanned host key with another fingerprint instead of trusting it on first use.
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
      SSH_HOST: ${{ secrets.SSH_HOST }}
      SSH_USER: ${{ secrets.SSH_USER }}
      SSH_KEY: ${{ secrets.SSH_KEY }}
      SSH_KNOWN_HOSTS: ${{ secrets.SSH_KNOWN_HOSTS }}
      SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
```
