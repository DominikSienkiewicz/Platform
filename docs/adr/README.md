# Architecture decision records — Platform

Decisions taken for this repository, in MADR-lite format: `Status` / `Context` / `Decision`
/ `Consequences`, plus `Revisit when` for decisions tied to a condition that will change.
The table below is generated from the ADR headers by `scripts/adr-index.sh`; CI fails when it is stale.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-platform-single-source-and-latest-version-rule.md) | Platform as the single source of shared artifacts, and the latest-in-portfolio rule | Accepted |
| [0002](0002-release-and-versioning-contract.md) | Release and versioning contract | Accepted |
| [0003](0003-local-platform-resolution.md) | Local platform resolution through an explicit platformRepository | Accepted |
| [0004](0004-consumer-toolchain-jdk-27.md) | Consumers compile for non-LTS JDK 27 while Gradle and build-logic run on JDK 25 | Accepted |
| [0005](0005-spotbugs-report-only.md) | SpotBugs stays report-only until a measurable exit criterion is met | Accepted |
| [0006](0006-pnpm-in-platform-npm-in-consumers.md) | pnpm in Platform's workspace, npm with a committed lockfile in consumers | Accepted |
| [0007](0007-public-naming.md) | Public naming of Platform artifacts and configuration keys | Accepted |
| [0008](0008-overrides-are-a-last-resort.md) | Overrides above the Boot BOM and npm overrides are a last resort, each with a removal condition | Accepted |
| [0009](0009-integration-tag-is-a-contract.md) | Test taxonomy — the `integration` JUnit tag is a public contract | Accepted |
| [0010](0010-agent-resource-profile.md) | Opt-in agent resource profile via AI_AGENT | Accepted |
| [0011](0011-contract-first-openapi.md) | Contract-first OpenAPI: the committed spec is the contract | Accepted |
| [0012](0012-platform-scans-itself-in-sonarqube-cloud.md) | Platform's own Java modules are analysed in SonarQube Cloud like a consumer | Accepted |
| [0013](0013-catalog-for-aliases-bom-for-constraints.md) | The catalog carries aliases and versions, platform-bom carries constraints | Accepted |
