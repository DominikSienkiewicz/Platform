# Architecture decision records — Platform

Decisions taken for this repository, in MADR-lite format: `Status` / `Context` / `Decision`
/ `Consequences`, plus `Revisit when` for decisions tied to a condition that will change.
Every settled decision of the maintainer's backlog has an ADR; Decision 23 was a fix to
`AbstractFlywayMigrationTest`, recorded in the CHANGELOG instead:

| Decisions | ADR |
| --- | --- |
| 1, 7, 29 (public showcase, incubating artifacts, GitHub Packages) | [0021](0021-public-showcase-and-incubating-artifacts.md) |
| 2, 4, 31; Conventional merge messages | [0002](0002-release-and-versioning-contract.md) |
| 3, 5, 27 (exact pins, the bump channel, template drift) | [0014](0014-exact-pins-moved-by-platform-bump.md) |
| 6 (unreleased changes through `platformRepository`) | [0003](0003-local-platform-resolution.md) |
| 8 (language) | [0022](0022-english-except-claude-md-and-comments.md) |
| 9 (rulesets) | [0015](0015-rulesets-protect-main-and-release-tags.md) |
| 10 (configuration cache) | [0023](0023-configuration-cache-is-supported.md) |
| 11, 12, 13 (roadmap toolkit) | [0024](0024-roadmap-toolkit-is-experimental.md) |
| 14, 15, 26 (self-scanning) | [0025](0025-platform-scans-itself.md) |
| 16 (production deploy gate) | [0016](0016-production-deploys-from-the-release-branch.md) |
| 18 (overrides above a BOM) | [0008](0008-overrides-are-a-last-resort.md) |
| 19 (pnpm and npm) | [0006](0006-pnpm-in-platform-npm-in-consumers.md) |
| 20, 21 (Platform's own npm dependencies, `strict`) | [0026](0026-platform-follows-its-frontend-canon.md) |
| 22, 34 (catalog entries, `PlatformVersions`) | [0020](0020-convention-versions-come-from-the-catalog.md) |
| 24, 28 (Sonar for multi-module consumers and for Platform) | [0012](0012-platform-scans-itself-in-sonarqube-cloud.md) |
| 25 (attestations) | [0017](0017-artifact-attestations-and-consumer-verification.md) |
| 30 (contract-first OpenAPI) | [0011](0011-contract-first-openapi.md) |
| 32, 35 (local adoption report and canary) | [0018](0018-private-consumer-data-stays-local.md) |
| 33 (warn first) | [0019](0019-new-failure-modes-warn-first.md) |
| 36 (platform-bom) | [0013](0013-catalog-for-aliases-bom-for-constraints.md) |
| 37 (Prometheus) | [0033](0033-prometheus-is-opt-in.md) |
| Gate codes, agent guidance, support window, quarantine, docs site, nullness, toolchain override (2026-10-19) | [0027](0027-gate-codes-are-a-contract.md), [0028](0028-agent-guidance-beside-claude-md.md), [0029](0029-support-window.md), [0030](0030-quarantine-with-a-deadline.md), [0031](0031-docs-site-with-zensical.md), [0032](0032-nullness-checking-is-opt-in.md), [0004](0004-consumer-toolchain-jdk-27.md) (carried over by [0034](0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md)) |

The table below is generated from the ADR headers by `scripts/adr-index.sh`; CI fails when it is stale.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-platform-single-source-and-latest-version-rule.md) | Platform as the single source of shared artifacts, and the latest-in-portfolio rule | Accepted |
| [0002](0002-release-and-versioning-contract.md) | Release and versioning contract | Accepted |
| [0003](0003-local-platform-resolution.md) | Local platform resolution through an explicit platformRepository | Accepted |
| [0004](0004-consumer-toolchain-jdk-27.md) | Consumers compile for non-LTS JDK 27 while Gradle and build-logic run on JDK 25 | Superseded |
| [0005](0005-spotbugs-report-only.md) | SpotBugs stays report-only until a measurable exit criterion is met | Accepted |
| [0006](0006-pnpm-in-platform-npm-in-consumers.md) | pnpm in Platform's workspace, npm with a committed lockfile in consumers | Accepted |
| [0007](0007-public-naming.md) | Public naming of Platform artifacts and configuration keys | Accepted |
| [0008](0008-overrides-are-a-last-resort.md) | Overrides above the Boot BOM and npm overrides are a last resort, each with a removal condition | Accepted |
| [0009](0009-integration-tag-is-a-contract.md) | Test taxonomy — the `integration` JUnit tag is a public contract | Accepted |
| [0010](0010-agent-resource-profile.md) | Opt-in agent resource profile via AI_AGENT | Accepted |
| [0011](0011-contract-first-openapi.md) | Contract-first OpenAPI: the committed spec is the contract | Accepted |
| [0012](0012-platform-scans-itself-in-sonarqube-cloud.md) | Platform's own Java modules are analysed in SonarQube Cloud like a consumer | Accepted |
| [0013](0013-catalog-for-aliases-bom-for-constraints.md) | The catalog carries aliases and versions, platform-bom carries constraints | Accepted |
| [0014](0014-exact-pins-moved-by-platform-bump.md) | Consumers pin exact releases, and platform-bump moves every pin | Accepted |
| [0015](0015-rulesets-protect-main-and-release-tags.md) | Rulesets protect main and the release tags without a required pull request | Accepted |
| [0016](0016-production-deploys-from-the-release-branch.md) | Production deploys run only from the release branch, with rollback by dispatch | Accepted |
| [0017](0017-artifact-attestations-and-consumer-verification.md) | Artifacts carry GitHub attestations, and consumers can verify them | Accepted |
| [0018](0018-private-consumer-data-stays-local.md) | Nothing about the private consumers runs in Platform's public CI | Accepted |
| [0019](0019-new-failure-modes-warn-first.md) | A new failure mode warns first and fails in a later MINOR | Accepted |
| [0020](0020-convention-versions-come-from-the-catalog.md) | The versions the convention plugins impose come from the catalog | Accepted |
| [0021](0021-public-showcase-and-incubating-artifacts.md) | A public showcase, with artifacts incubating until a consumer adopts them | Accepted |
| [0022](0022-english-except-claude-md-and-comments.md) | English everywhere, Polish only in CLAUDE.md and in code comments | Accepted |
| [0023](0023-configuration-cache-is-supported.md) | The configuration cache is supported and gated in TestKit | Accepted |
| [0024](0024-roadmap-toolkit-is-experimental.md) | The roadmap toolkit is experimental; only its marker contract is stable | Accepted |
| [0025](0025-platform-scans-itself.md) | Platform scans itself with the scanners it offers | Accepted |
| [0026](0026-platform-follows-its-frontend-canon.md) | Platform's own npm dependencies follow its frontend canon | Accepted |
| [0027](0027-gate-codes-are-a-contract.md) | Gate codes are a public contract | Accepted |
| [0028](0028-agent-guidance-beside-claude-md.md) | Agent guidance: AGENTS.md beside CLAUDE.md, and a managed block in consumers | Accepted |
| [0029](0029-support-window.md) | Support window: the latest MINOR, at most 3 releases or 60 days behind | Accepted |
| [0030](0030-quarantine-with-a-deadline.md) | Flaky tests: quarantine with a deadline, and retries that keep the build red | Accepted |
| [0031](0031-docs-site-with-zensical.md) | A documentation site built with Zensical, deployed when the owner enables Pages | Accepted |
| [0032](0032-nullness-checking-is-opt-in.md) | Nullness checking is opt-in | Accepted |
| [0033](0033-prometheus-is-opt-in.md) | Prometheus is opt-in in the observability starter | Accepted |
| [0034](0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md) | One JDK 27 runs Gradle, compiles build-logic and is the consumer toolchain | Accepted |
