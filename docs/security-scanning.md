# Security scanning

Which scans the reusable workflows run, what fails a build, and how a consumer accepts a finding it
cannot fix yet. The caller side of each workflow is in [reusable-workflows.md](reusable-workflows.md).

## Gates

| Scan | Workflow | Fails on | Accepting a finding |
|---|---|---|---|
| Grype on the backend CycloneDX SBOM | `security-scan.yml` | severity at or above `severity-cutoff` (default `high`); with `only-fixed: true`, only findings that have a fix | `.grype.yaml` |
| Grype on `frontend/package-lock.json` | `security-scan.yml` | the same | `.grype.yaml` |
| Grype on the pushed images, by digest | `deploy.yml` with `scan-images: true` | severity at or above `scan-severity`, fixable findings only | `.grype.yaml` |
| Trivy on the pushed images, by digest | `deploy.yml` with `scan-images: true` | the same; every image is scanned before the step fails | `.trivyignore.yaml` |
| Grype on published images | `container-scan.yml` | severity at or above `severity-cutoff`, fixable findings only by default | `only-fixed` and `severity-cutoff`; the job does not check the repository out, so `.grype.yaml` does not apply |
| Semgrep | `semgrep.yml` | findings of severity `CRITICAL`, `HIGH` or `ERROR`; `MEDIUM`, `WARNING`, `LOW` and `INFO` are listed and counted only | `# nosemgrep: <rule-id>` |
| Snyk | `container-scan.yml`, `deploy.yml` | never: advisory only | — |
| CodeQL (Platform only, not reusable) | `codeql.yml` | never: alerts go to Code scanning | dismiss the alert in Code scanning with a reason |

`only-fixed` differs on purpose. `container-scan.yml` defaults to `true`, because base images carry
HIGH OS findings without a fix that would keep it red forever. `security-scan.yml` defaults to
`false`: a dependency finding without a fix is still worth a decision, which the exception records.

## Accepting a finding

An accepted finding is a decision with an owner and an end date, not a silenced scanner.

1. Open an issue for the finding: what is affected, why it cannot be fixed now, and what would fix it.
2. Add an entry to `.grype.yaml` in the repository root, starting from
   [`templates/grype.yaml`](../templates/grype.yaml). The comment line right above the entry is
   mandatory:

   ```yaml
   ignore:
     # expires: 2026-12-31; tracking: https://github.com/OWNER/REPO/issues/123; reason: no fixed undici release yet
     - vulnerability: GHSA-xxxx-xxxx-xxxx
       package:
         name: undici
   ```

   Narrow the entry with `package` whenever the same ID could hit another package. Pick an expiry
   that forces a second look: weeks, not years.
3. When the date passes, `security-scan.yml` fails with the entry and its line. Fix the finding, or
   renew the entry with a new date and the outcome recorded in the issue. An entry without a date
   only produces a warning, so add one when you see it.
4. When the finding is in a pushed image, accept it for Trivy too, because both scanners gate
   `deploy.yml`. Add an entry to `.trivyignore.yaml` in the repository root, in Trivy's own format.
   Trivy honours `expired_at` itself: after that date the entry stops applying and the gate fails again.

   ```yaml
   vulnerabilities:
     - id: GHSA-xxxx-xxxx-xxxx
       expired_at: 2026-12-31
       statement: "tracking: https://github.com/OWNER/REPO/issues/123; reason: no fixed undici release yet"
   ```

   Narrow the entry with `paths` or `purls` whenever the same ID could hit another package.

OpenSSF Scorecard's Vulnerabilities check runs osv-scanner over every lockfile of the repository and
counts each advisory, fixed or not. Platform records an accepted advisory for it in an `osv-scanner.toml`
next to the lockfile, for example [`frontend/osv-scanner.toml`](../frontend/osv-scanner.toml): one
`[[IgnoredVulns]]` entry per ID with `ignoreUntil` and `reason`. osv-scanner stops honouring the entry
after that date, so the advisory counts again until it is fixed or renewed.

## Signed images

With `scan-images: true`, `deploy.yml` signs every image it scanned, and only after both gates pass
([ADR-0036](adr/0036-images-signed-keyless-after-the-gates.md)). An image that a gate rejects is already in
GHCR, because the scan pulls it from there, but it stays unsigned. A cluster that admits only signed images
therefore never runs it.

- **What is signed.** The `build-push` job resolves the backend tag, and the frontend tag unless
  `single-image` is set, to a digest once. Grype and Trivy scan that digest, and the `sign` job signs the same
  digest. The migration and `eval-worker` images are not scanned, so they are not signed either.
- **How.** cosign keyless, through the public Sigstore instance. The certificate comes from the job's GitHub
  OIDC token, so no signing key exists. The signature is a Sigstore bundle, attached to the image in GHCR as
  an OCI referrer (cosign 3). Fulcio's certificate transparency log and Rekor record the certificate and the
  signature publicly: they name the calling repository, its workflow and branch, the commit and the image
  digest.
- **Who signs.** Only the `sign` job holds `id-token: write`. It checks nothing out and runs no code of the
  repository, so dependency code that runs during the build cannot sign anything.
- **Identity.** The certificate names the reusable workflow, not the caller's:

  | Field | Value |
  |---|---|
  | Issuer | `https://token.actions.githubusercontent.com` |
  | Subject (SAN) | `https://github.com/DominikSienkiewicz/Platform/.github/workflows/deploy.yml@<ref>`, where `<ref>` is the ref the caller's `uses:` names: a commit SHA when `promote.yml` calls it, `refs/tags/vX.Y.Z` for a direct caller |
  | Source repository (`githubWorkflowRepository`, OID 1.3.6.1.4.1.57264.1.5) | the calling repository, for example `DominikSienkiewicz/Azimuth` |
  | Source ref (`githubWorkflowRef`, OID 1.3.6.1.4.1.57264.1.6) | the branch of the calling run, `refs/heads/release` for a promotion |
  | Trigger (`githubWorkflowTrigger`, OID 1.3.6.1.4.1.57264.1.2) | `push`, or `workflow_dispatch` for a manual run |
  | Predicate type of the signed statement | `https://sigstore.dev/cosign/sign/v1` |

Verify one image by hand, by tag or by digest:

```bash
cosign verify ghcr.io/owner/myapp-backend:1.2.3 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github\.com/DominikSienkiewicz/Platform/\.github/workflows/deploy\.yml@' \
  --certificate-github-workflow-repository owner/myapp
```

Semgrep findings follow the same convention: the comment line above `# nosemgrep: <rule-id>` carries
`expires`, `tracking` and `reason`. Name the rule ID: a bare `# nosemgrep` silences every rule on that
line. Nothing checks these dates automatically yet, so they are reviewed with the change that adds them.

## Platform's own frontend workspace

[`frontend/pnpm-workspace.yaml`](../frontend/pnpm-workspace.yaml) sets `trustPolicy: no-downgrade`: pnpm
refuses a package version with weaker trust evidence (trusted publisher, provenance) than a version of that
package published before it, and `pnpm install --frozen-lockfile` fails with `TRUST_DOWNGRADE`. pnpm compares
versions by publish date, so a backport of an older major published after the next major gained provenance
trips it too. Check that the flagged version is such a backport and not a takeover, then add the exact
`name@version` to `trustPolicyExclude` with the reason in a comment. `blockExoticSubdeps: true` keeps
transitive dependencies on the registry. `minimumReleaseAge` stays at the pnpm 11 default of one day,
non-strict, so Semgrep's `pnpm-minimum-release-age` finding, which asks for seven days, remains a log-only
advisory, as does `npm-missing-minimum-release-age` on `frontend/.npmrc`, from which pnpm reads only
registry and authentication settings.
