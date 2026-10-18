# Security scanning

Which scans the reusable workflows run, what fails a build, and how a consumer accepts a finding it
cannot fix yet. The caller side of each workflow is in [reusable-workflows.md](reusable-workflows.md).

## Gates

| Scan | Workflow | Fails on | Accepting a finding |
|---|---|---|---|
| Grype on the backend CycloneDX SBOM | `security-scan.yml` | severity at or above `severity-cutoff` (default `high`); with `only-fixed: true`, only findings that have a fix | `.grype.yaml` |
| Grype on `frontend/package-lock.json` | `security-scan.yml` | the same | `.grype.yaml` |
| Grype on the pushed images | `deploy.yml` with `scan-images: true` | severity at or above `scan-severity`, fixable findings only | `.grype.yaml` |
| Grype on published images | `container-scan.yml` | severity at or above `severity-cutoff`, fixable findings only by default | `only-fixed` and `severity-cutoff`; the job does not check the repository out, so `.grype.yaml` does not apply |
| Semgrep | `semgrep.yml` | findings of severity `ERROR` | `# nosemgrep: <rule-id>` |
| Snyk | `container-scan.yml`, `deploy.yml` | never: advisory only | — |

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

Semgrep findings follow the same convention: the comment line above `# nosemgrep: <rule-id>` carries
`expires`, `tracking` and `reason`. Name the rule ID: a bare `# nosemgrep` silences every rule on that
line. Nothing checks these dates automatically yet, so they are reviewed with the change that adds them.
