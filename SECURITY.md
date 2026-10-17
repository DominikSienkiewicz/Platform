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

## Scope

In scope:

- the published Maven artifacts: the convention plugins, the version catalog, `test-fixtures` and
  `security-starter`;
- the published npm packages under `@dominiksienkiewicz/`;
- the reusable workflows in `.github/workflows/`;
- the scripts consumers run or copy from this repository (`scripts/`, `templates/`).

A dependency version pinned by the platform that has a **publicly disclosed** CVE is already
public. Report it as a regular issue or pull request against `gradle/catalog/libs.versions.toml` or
`frontend/packages/versions/versions.json`. Vulnerabilities in third-party projects themselves
belong with those projects.
