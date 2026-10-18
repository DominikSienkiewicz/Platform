# Architecture decision records — Platform

Decisions taken for this repository, in MADR-lite format: `Status` / `Context` / `Decision`
/ `Consequences`, plus `Revisit when` for decisions tied to a condition that will change.

| # | Decision | Status |
| --- | --- | --- |
| [0001](0001-platform-single-source-and-latest-version-rule.md) | Platform as the single source of shared artifacts, and the latest-in-portfolio rule | Accepted |
| [0002](0002-release-and-versioning-contract.md) | Release and versioning contract | Accepted |
| [0003](0003-local-platform-resolution.md) | Local platform resolution through an explicit platformRepository | Accepted |
| [0004](0004-consumer-toolchain-jdk-27.md) | Consumers compile for non-LTS JDK 27 while Gradle and build-logic run on JDK 25 | Accepted |
| [0005](0005-spotbugs-report-only.md) | SpotBugs stays report-only until a measurable exit criterion is met | Accepted |
| [0006](0006-pnpm-in-platform-npm-in-consumers.md) | pnpm in Platform's workspace, npm with a committed lockfile in consumers | Accepted |
