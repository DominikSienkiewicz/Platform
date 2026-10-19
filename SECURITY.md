# Security policy

## Supported versions

| Version | Supported |
|---|---|
| Newest `1.x` release | Yes |
| Any older release | No |

Published versions are immutable, so a fix is never patched into an existing version. It ships as
a new release, and consumers pick it up by bumping their platform pin. The reusable workflows that
consumers call via `@v1` always point at the newest `1.x` release.

## Reporting a vulnerability

Report privately. Do not open a public issue, pull request or discussion for a vulnerability.

Use GitHub Private Vulnerability Reporting: open the
[Security tab](https://github.com/DominikSienkiewicz/Platform/security) and choose
**Report a vulnerability**, or go straight to the
[new advisory form](https://github.com/DominikSienkiewicz/Platform/security/advisories/new).

Please include:

- the affected artifact (Maven coordinates, npm package or workflow file) and its version;
- what an attacker can achieve, and under which conditions;
- steps to reproduce or a proof of concept;
- a suggested fix, if you have one.

Reports are acknowledged within seven days. The fix and the advisory are published together, and
you are credited in the advisory unless you ask not to be.

## Security mechanisms

- Secret scanning with push protection and Dependabot alerts are on for this repository. Dependabot's
  security-update pull requests are off, because `platform-bump` moves every version consumers get.
- Every action in `.github/workflows/` is pinned by commit SHA, and the repository requires it.
- Repository rulesets keep `main` from being deleted or force-pushed and release tags from being moved
  or deleted.
- `release.yml` publishes only from a tag on a commit with green CI, and attests the provenance of every
  published file; [docs/consuming.md](docs/consuming.md#verifying-provenance) shows how to verify it.
- `canon-cve-scan.yml` scans the versions Platform imposes every week, and `self-scan.yml` runs
  Scorecard and Semgrep on Platform itself.

`scripts/repo-settings.sh --check` shows whether the repository settings above are in place.

## Scope

In scope:

- the published Maven artifacts: the convention plugins, the version catalog, `test-fixtures` and
  `security-starter`;
- the published npm packages under `@dominiksienkiewicz/`;
- the reusable workflows in `.github/workflows/`;
- the scripts consumers run or copy from this repository (`scripts/`, `templates/`).

A dependency version pinned by the platform that has a **publicly disclosed** CVE is already
public. Report it as a regular issue or pull request against `gradle/catalog/libs.versions.toml` or
`frontend/packages/versions/versions.json`. The weekly `canon-cve-scan.yml` looks for such versions,
and [docs/versions.md](docs/versions.md#cve-response) describes how they are fixed. Vulnerabilities in
third-party projects themselves belong with those projects.
