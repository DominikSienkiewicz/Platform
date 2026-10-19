# OpenSSF Best Practices self-assessment

Platform's answers to the *passing* level of the [OpenSSF Best Practices badge](https://www.bestpractices.dev/en/criteria/0):
for every criterion, the evidence in this repository, or the reason there is none. The criteria were read from that
page on 2026-10-19; it listed 67 at the passing level. This page is the working copy for the form. It earns nothing
by itself: the maintainer enters the answers on [bestpractices.dev](https://www.bestpractices.dev), and the README
shows no badge until the badge is earned.

| Status | Meaning |
|---|---|
| **Met** | the evidence named in the row exists in this repository |
| **N/A** | the criterion does not apply; the row carries the justification the form asks for |
| **Not met** | no evidence today; the row says what it would take |
| **Owner action** | the answer depends on something only the maintainer can state or check, or the evidence is partial |

Of the 67 criteria, 45 are **Met**, 11 **N/A**, 2 **Not met** (both SUGGESTED) and 9 **Owner action**. Six of the
Owner actions are MUST criteria; they are listed in [what is left](#what-is-left) with the answer to give each.

## Basics

| Criterion | Level | Status | Evidence |
|---|---|---|---|
| `description_good` | MUST | **Met** | [README](../README.md) opens with what Platform is and has a "Why this exists" section. |
| `interact` | MUST | **Met** | [README](../README.md#try-it-without-credentials) shows how to obtain a release; [CONTRIBUTING](../CONTRIBUTING.md) explains feedback and contributions; the [issue forms](../.github/ISSUE_TEMPLATE/bug.yml) take reports. |
| `contribution` | MUST | **Met** | [CONTRIBUTING](../CONTRIBUTING.md): issues first, pull requests after the issue is agreed. |
| `contribution_requirements` | SHOULD | **Met** | [CONTRIBUTING](../CONTRIBUTING.md) "Rules a change must follow" and "The gate"; hard rules in [AGENTS.md](../AGENTS.md). |
| `floss_license` | MUST | **Met** | MIT, in [LICENSE](../LICENSE). |
| `floss_license_osi` | SUGGESTED | **Met** | MIT is OSI-approved. |
| `license_location` | MUST | **Met** | [LICENSE](../LICENSE) at the repository root; the licence is also in the metadata of every Maven POM and npm package ([README](../README.md#license)). |
| `documentation_basics` | MUST | **Met** | [README](../README.md), [consuming Platform](consuming.md) and [local development](local-development.md). |
| `documentation_interface` | MUST | **Met** | [Reference](reference.md) lists every task, property and default; [reusable workflows](reusable-workflows.md) lists their inputs, secrets and permissions; [gate codes](gates.md) lists the failures. |
| `sites_https` | MUST | **Met** | The repository, GitHub Releases and GitHub Packages (Maven and npm) are served over HTTPS; the documentation site is built for GitHub Pages ([`docs-site.yml`](../.github/workflows/docs-site.yml)), which serves HTTPS once the maintainer enables it. |
| `discussion` | MUST | **Met** | GitHub issues and pull requests: searchable, one URL per topic, no proprietary client. |
| `english` | SHOULD | **Met** | README, `docs/`, the issue forms and the release notes are in English ([README](../README.md#documentation-language)), and reports are accepted in English. `CLAUDE.md` and code comments are Polish, and are maintainer-facing. |
| `maintained` | MUST | **Met** | Active history on `main`, a [changelog](../CHANGELOG.md) with an `[Unreleased]` section, and weekly scheduled workflows ([`ci.yml`](../.github/workflows/ci.yml), [`canon-cve-scan.yml`](../.github/workflows/canon-cve-scan.yml), [`reproducibility.yml`](../.github/workflows/reproducibility.yml)). |

## Change control

| Criterion | Level | Status | Evidence |
|---|---|---|---|
| `repo_public` | MUST | **Met** | The public repository `DominikSienkiewicz/Platform` on GitHub. |
| `repo_track` | MUST | **Met** | Git records what changed, who changed it and when. |
| `repo_interim` | MUST | **Met** | Work lands on the public `main` before any release; [`release-draft.yml`](../.github/workflows/release-draft.yml) keeps a draft release of the unreleased state. |
| `repo_distributed` | SUGGESTED | **Met** | Git. |
| `version_unique` | MUST | **Met** | One `platformVersion` per release, tagged `vX.Y.Z`; a version is never republished ([ADR-0002](adr/0002-release-and-versioning-contract.md)). |
| `version_semver` | SUGGESTED | **Owner action** | The format is `MAJOR.MINOR.PATCH`, but ADR-0002 makes a MINOR carry consumer action and says it deviates from strict SemVer on purpose. Recommended answer: Met, with that sentence as the justification. |
| `version_tags` | SUGGESTED | **Met** | Annotated tags `vX.Y.Z` made by `release.sh`, protected by [`release-tags.json`](../.github/rulesets/release-tags.json). |
| `release_notes` | MUST | **Met** | [CHANGELOG](../CHANGELOG.md) has a section per version with "Consumer action required"; [`release.yml`](../.github/workflows/release.yml) publishes it as the GitHub Release through [`changelog-section.sh`](../scripts/changelog-section.sh). |
| `release_notes_vulns` | MUST | **Owner action** | The [CVE response](versions.md#cve-response) procedure now requires the CVE ids in the `CHANGELOG.md` entry of a release that fixes a vulnerability, so it is met from the next release. Published releases name no ids, and the `[Unreleased]` entry on the Tomcat, Jackson, jsoup and js-yaml bumps in [CHANGELOG](../CHANGELOG.md) names none yet; add them before that release is cut. |

## Reporting

| Criterion | Level | Status | Evidence |
|---|---|---|---|
| `report_process` | MUST | **Met** | [CONTRIBUTING](../CONTRIBUTING.md) points to the issue forms; [`config.yml`](../.github/ISSUE_TEMPLATE/config.yml) turns blank issues off. |
| `report_tracker` | SHOULD | **Met** | GitHub Issues. |
| `report_responses` | MUST | **Owner action** | Depends on the last 2 to 12 months of the tracker. Count the reports without an acknowledgement before applying; the evidence is the issue list, not a file. |
| `enhancement_responses` | SHOULD | **Owner action** | The same check for enhancement requests (the [library-request](../.github/ISSUE_TEMPLATE/library-request.yml) and [adoption](../.github/ISSUE_TEMPLATE/adoption-request.yml) forms). |
| `report_archive` | MUST | **Met** | GitHub Issues are public and searchable. |
| `vulnerability_report_process` | MUST | **Met** | [SECURITY.md](../SECURITY.md), shown in the repository's Security tab. |
| `vulnerability_report_private` | MUST | **Met** | GitHub Private Vulnerability Reporting, described in [SECURITY.md](../SECURITY.md); `repo-settings.sh --check` ([`repo-settings.sh`](../scripts/repo-settings.sh)) reports whether the setting is on. |
| `vulnerability_report_response` | MUST | **Owner action** | [SECURITY.md](../SECURITY.md) promises an acknowledgement within seven days, inside the 14 allowed. Whether it held depends on the reports of the last 6 months; with none, answer N/A. |

## Quality

| Criterion | Level | Status | Evidence |
|---|---|---|---|
| `build` | MUST | **Met** | Gradle wrappers and pnpm build everything from source ([local development](local-development.md)); [`ci.yml`](../.github/workflows/ci.yml) rebuilds on every push and pull request, and [`reproducibility.yml`](../.github/workflows/reproducibility.yml) rebuilds the latest tag and compares jar digests. |
| `build_common_tools` | SUGGESTED | **Met** | Gradle and pnpm. |
| `build_floss_tools` | SHOULD | **Met** | JDK, Gradle, Node and pnpm are all FLOSS. |
| `test` | MUST | **Met** | JUnit suites in the Java modules, Vitest in `frontend/`, and shell tests in [`templates/tests/`](../templates/tests/); how to run them is in [CONTRIBUTING](../CONTRIBUTING.md#the-gate). |
| `test_invocation` | SHOULD | **Met** | `./gradlew test`, `pnpm test` and `bash templates/tests/<name>.test.sh`. |
| `test_most` | SUGGESTED | **Owner action** | The four published Java modules gate JaCoCo coverage at 0.88 to 0.95 (`coverageMinimum` in each `gradle.properties`) and every script has a test, but frontend and workflow coverage is not measured. Answer Met only if that counts as most. |
| `test_continuous_integration` | SUGGESTED | **Met** | [`ci.yml`](../.github/workflows/ci.yml) runs the test suites on each push to `main`, each pull request and every Monday. |
| `test_policy` | MUST | **Met** | [CONTRIBUTING](../CONTRIBUTING.md) "Rules a change must follow": new functionality comes with tests that cover it, and a bug fix starts with a regression test. The coverage thresholds (`coverageMinimum` 0.88 to 0.95) enforce it in the four published Java modules. |
| `tests_are_added` | MUST | **Met** | Recent features carry their guard, for example [`platform-plugin.test.sh`](../templates/tests/platform-plugin.test.sh) with the Claude Code plugin and [`ci-frontend-image.test.sh`](../templates/tests/ci-frontend-image.test.sh) with the frontend image build. |
| `tests_documented_added` | SUGGESTED | **Met** | The rule is in the change instructions: [CONTRIBUTING](../CONTRIBUTING.md) and the checklist of Platform's [pull request template](../.github/pull_request_template.md). |
| `warnings` | MUST | **Met** | Checkstyle and Spotless in the Java modules, ESLint and Prettier in the frontend, ShellCheck over every tracked script (the `shellcheck` job of [`ci.yml`](../.github/workflows/ci.yml)). |
| `warnings_fixed` | MUST | **Met** | Checkstyle runs with `maxWarnings=0`, so a warning fails `check`; a ShellCheck finding fails its CI job. |
| `warnings_strict` | SUGGESTED | **Met** | `maxWarnings=0`, ShellCheck at `--severity=warning`, and `strict: true` for the frontend CI. |

## Security

| Criterion | Level | Status | Evidence |
|---|---|---|---|
| `know_secure_design` | MUST | **Owner action** | A statement about the maintainer's knowledge. Supporting material: [SECURITY.md](../SECURITY.md) "Security mechanisms", [security scanning](security-scanning.md), actions pinned by SHA, `permissions:` set per workflow, and the [rulesets](../.github/rulesets/main.json). |
| `know_common_errors` | MUST | **Owner action** | The same statement, for common error types and their mitigations. |
| `crypto_published` | MUST | **N/A** | Platform contains no cryptographic code. The security starter configures Spring Security and delegates TLS and token handling to it. |
| `crypto_call` | SHOULD | **N/A** | Nothing is re-implemented; see `crypto_published`. |
| `crypto_floss` | MUST | **N/A** | No cryptographic functionality of its own. |
| `crypto_keylength` | MUST | **N/A** | No keys are generated or configured by default. |
| `crypto_working` | MUST | **N/A** | No algorithm is chosen by Platform. |
| `crypto_weaknesses` | SHOULD | **N/A** | No algorithm is chosen by Platform. |
| `crypto_pfs` | SHOULD | **N/A** | Platform implements no key agreement. |
| `crypto_password_storage` | MUST | **N/A** | Platform stores no passwords. |
| `crypto_random` | MUST | **N/A** | Platform generates no keys or nonces. |
| `delivery_mitm` | MUST | **Met** | Artifacts come from GitHub Packages and GitHub Releases over HTTPS; [`release.yml`](../.github/workflows/release.yml) attests the provenance of every published file and [consuming](consuming.md#verifying-provenance) shows how to verify it. |
| `delivery_unsigned` | MUST | **Met** | No script, workflow or template fetches a hash over HTTP; `SHA256SUMS` is a release asset that is itself attested. |
| `vulnerabilities_fixed_60_days` | MUST | **Owner action** | The process exists ([CVE response](versions.md#cve-response): weekly [`canon-cve-scan.yml`](../.github/workflows/canon-cve-scan.yml), a fix within seven days, three for CRITICAL), but the scan fails on HIGH and CRITICAL only. Before applying, check the Security tab for medium alerts older than 60 days. |
| `vulnerabilities_critical_fixed` | SHOULD | **Met** | The [CVE response](versions.md#cve-response) commits to a patch release within three days of a CRITICAL finding. |
| `no_leaked_credentials` | MUST | **Met** | Secret scanning with push protection is on and checked by [`repo-settings.sh`](../scripts/repo-settings.sh); the Semgrep rules in [`semgrep.yml`](../.github/workflows/semgrep.yml) include `p/secrets`; `.env` files are ignored. |

## Analysis

| Criterion | Level | Status | Evidence |
|---|---|---|---|
| `static_analysis` | MUST | **Met** | Semgrep ([`semgrep.yml`](../.github/workflows/semgrep.yml), run on Platform by [`self-scan.yml`](../.github/workflows/self-scan.yml)), Checkstyle, SpotBugs (report-only, [ADR-0005](adr/0005-spotbugs-report-only.md)) and SonarCloud (the `sonar` job of [`ci.yml`](../.github/workflows/ci.yml), while the `SONAR_TOKEN` secret exists). |
| `static_analysis_common_vulnerabilities` | SUGGESTED | **Met** | Semgrep's `p/default`, `p/secrets`, `p/java`, `p/javascript`, `p/typescript`, `p/dockerfile` and `p/github-actions` rulesets. |
| `static_analysis_fixed` | MUST | **Met** | A Semgrep finding of severity CRITICAL, HIGH or ERROR fails the job, so it blocks the change until it is fixed or explicitly accepted with `# nosemgrep` ([security scanning](security-scanning.md)). |
| `static_analysis_often` | SUGGESTED | **Met** | [`self-scan.yml`](../.github/workflows/self-scan.yml) runs on every push to `main`, every pull request and every Monday. |
| `dynamic_analysis` | SUGGESTED | **Not met** | No fuzzer or dynamic scanner runs against a release. Integration tests with Testcontainers and mutation testing are tests, not dynamic analysis tools. |
| `dynamic_analysis_unsafe` | SUGGESTED | **N/A** | Platform produces no memory-unsafe code: there is no C or C++ in it. |
| `dynamic_analysis_enable_assertions` | SUGGESTED | **Not met** | Follows `dynamic_analysis`: without a dynamic tool there is nothing to run with assertions enabled. |
| `dynamic_analysis_fixed` | MUST | **N/A** | No dynamic analysis runs, so none reports a vulnerability to fix. |

## What is left

The six MUST criteria marked **Owner action**, each with the answer to give:

1. `know_secure_design` and `know_common_errors`: the maintainer attests on the form. Nothing to change in the repository.
2. `report_responses` and `vulnerability_report_response`: read the tracker and the advisories of the last 12 and 6 months.
   With no vulnerability reports in 6 months, answer N/A for the second.
3. `vulnerabilities_fixed_60_days`: open the Security tab and clear every alert older than 60 days, medium included.
4. `release_notes_vulns`: put the CVE ids of the Tomcat, Jackson, jsoup and js-yaml bumps into their `[Unreleased]`
   entry before the next release is cut. From that release the criterion is met.

## Applying

Sign in to [bestpractices.dev](https://www.bestpractices.dev) with GitHub, add `https://github.com/DominikSienkiewicz/Platform`
and answer each criterion with the evidence above. Once the badge is earned, its snippet can go into the README; until
then the README carries none.
