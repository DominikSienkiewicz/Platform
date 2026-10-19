# Security policy

## Supported versions

Unless a repository's own security policy says otherwise, only its latest release receives security fixes; a
repository without releases supports its default branch. A fix ships as a new release, not as a change to a
published one.

## Reporting a vulnerability

Report privately. Do not open a public issue, pull request or discussion for a vulnerability.

Use GitHub Private Vulnerability Reporting: open the **Security** tab of the repository the vulnerability concerns
and choose **Report a vulnerability**. If the tab has no such button, private reporting is not enabled for that
repository: ask the maintainer for a private channel through the contact on
[the maintainer's GitHub profile](https://github.com/DominikSienkiewicz), and do not describe the vulnerability in
public.

Please include:

- the affected component and its version or commit;
- what an attacker can achieve, and under which conditions;
- steps to reproduce or a proof of concept;
- a suggested fix, if you have one.

Reports are acknowledged within seven days. The fix and the advisory are published together, and you are credited in
the advisory unless you ask not to be.

## Scope

In scope is the code of the repository the report concerns.

A dependency version with a **publicly disclosed** CVE is already public. Report it as a regular issue or pull
request that updates the version. Vulnerabilities in third-party projects themselves belong with those projects.
