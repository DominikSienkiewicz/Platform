# Platform

**Designed and maintained by [Dominik Sienkiewicz](https://www.linkedin.com/in/dominik-sienkiewicz/), built with AI coding agents:** I set the architecture, write the specifications, define the quality gates enforced in CI and review every change. How that works: [engineering with agents](docs/engineering-with-agents.md).

A shared build platform for a multi-repository JVM and frontend organisation. Build
configuration, quality gates, the versions of the shared frame and frontend presets live here once,
are published as versioned artifacts, and are consumed like any other dependency.

![Java 27](https://img.shields.io/badge/Java-27-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Gradle 9](https://img.shields.io/badge/Gradle-9-02303A?style=for-the-badge&logo=gradle&logoColor=white)
![Kotlin DSL](https://img.shields.io/badge/Kotlin-DSL-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white)
![TypeScript 6](https://img.shields.io/badge/TypeScript-6-3178C6?style=for-the-badge&logo=typescript&logoColor=white)
![pnpm 11](https://img.shields.io/badge/pnpm-11-F69220?style=for-the-badge&logo=pnpm&logoColor=white)

[![CI](https://github.com/DominikSienkiewicz/Platform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DominikSienkiewicz/Platform/actions/workflows/ci.yml)
[![Latest version](https://img.shields.io/github/v/tag/DominikSienkiewicz/Platform?filter=v*.*.*&sort=semver&label=version)](https://github.com/DominikSienkiewicz/Platform/tags)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Reviewing this repository?** Start with [the tour](docs/tour.md): nine stops, each a problem, the code that
solves it and the guard that keeps it solved, with [incident notes](docs/notes/) behind several of them.

> Registry: **GitHub Packages** (Maven + npm). Frontend workspaces: **pnpm** in this repository;
> consumers use **npm** with a committed `package-lock.json`, because `frontend-ci` runs `npm ci`
> and `platform-bump` updates that lockfile.

## Why this exists

Several product repositories grew from one template and drifted apart — different
formatters, different dependency versions, the same fix applied three times or forgotten
in two. Copying configuration between repositories is what caused the drift, so the
platform does not copy it: it publishes it.

The reason this is a separate repository rather than shared build logic is a constraint,
not a preference. **`buildSrc` and composite builds are scoped to a single repository** —
neither can be consumed across a repository boundary. A published, versioned artifact is
the only mechanism that crosses that boundary, which also means a consumer upgrades on its
own schedule and rolls back by pinning an older version.

Platform governs the frame, not every dependency
([ADR-0037](docs/adr/0037-platform-governs-the-frame.md)). The frame is Java, Gradle, the Spring BOMs,
the libraries in the catalog and the frontend canon. A consumer cannot give them another version, and an
explicit version of a library a Spring or Platform BOM manages fails the build
([gates](docs/gates.md#gradle)). A library only one repository uses belongs to that repository: a Gradle
build declares it in a second catalog `appLibs` read from `backend/gradle/app.versions.toml`, a frontend
pins its exact version in `package.json`, and neither needs a Platform release. A library joins the frame
when a second repository needs it.

## What it publishes

| Path | Artifact | Published to |
|---|---|---|
| `gradle/build-logic/` | six convention plugins (`seniordev.*-conventions`, including settings, the multi-module Sonar root and the opt-in nullness check) | GitHub Packages (Maven) |
| `gradle/catalog/` | version catalog (`pl.seniordeveloper:platform-catalog`) with the libraries and plugins of the frame | GitHub Packages (Maven) |
| `gradle/bom/` | `pl.seniordeveloper:platform-bom` — imports of the Spring BOMs, CVE floors and compatibility overrides with their reasons, from the catalog's versions | GitHub Packages (Maven) |
| `gradle/observability-starter/` | `pl.seniordeveloper:platform-observability-starter` — actuator, probes and metrics defaults, opt-in Prometheus and a `tracing` feature, with which a server span answered 5xx has the status `ERROR` | GitHub Packages (Maven) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers, test databases, migration and OpenAPI contract guards) | GitHub Packages (Maven) |
| `frontend/packages/tsconfig/` | `@dominiksienkiewicz/tsconfig` | GitHub Packages (npm) |
| `frontend/packages/eslint-config/` | `@dominiksienkiewicz/eslint-config` | GitHub Packages (npm) |
| `frontend/packages/tailwind-preset/` | `@dominiksienkiewicz/tailwind-preset` (CSS-first `@theme`) | GitHub Packages (npm) |
| `frontend/packages/vitest-config/` | `@dominiksienkiewicz/vitest-config` (jsdom + Testing Library) | GitHub Packages (npm) |
| `frontend/packages/prettier-config/` | `@dominiksienkiewicz/prettier-config` — Prettier with the Tailwind class sorter | GitHub Packages (npm) |
| `frontend/packages/versions/` | `@dominiksienkiewicz/versions` — the frontend version canon, the `platform-versions-check` guard that `frontend-ci` runs in strict mode, the `platform-bump` bin, the `platform-templates-check` drift report, `platform-workflows-check`, which holds callers to the reusable workflow contract, and `platform-doctor`, which diagnoses a repository against Platform's preconditions | GitHub Packages (npm) |
| `frontend/packages/openapi/` | `@dominiksienkiewicz/openapi` — `platform-openapi-gen` and `platform-openapi-check`: TypeScript types generated from the committed OpenAPI spec | GitHub Packages (npm) |
| `.github/workflows/` | ten reusable workflows, listed [below](#reusable-workflows) | called as `uses: …@vX.Y.Z` |
| `default.json` | shared Renovate preset for GitHub Actions and Docker images; Platform pins move with `platform-bump` | `extends: github>DominikSienkiewicz/Platform` |
| `templates/` | canonical files every repository keeps a copy of: the JVM starters, `.editorconfig`, `.sdkmanrc`, the `.gitignore` set, `Dockerfile.backend`, `npmrc`, `grype.yaml`, the scripts `merge.sh`, `platform-bump.sh` (stub), `bump-version.sh` and `agent-gradle.sh`, and the GitHub files; each one is listed in [templates/README.md](templates/README.md) | copied; `platform-templates-check` reports drift |
| `releases/yanked.txt` | releases `platform-bump` no longer offers, with the reason and the replacement ([runbook](docs/runbooks/rollback.md)) | read from `main` by `platform-bump` |
| `scripts/` | scripts Platform's own workflows run: `promote-image.sh` (sets the image tags in a GitOps repository, run by `promote.yml`), `changelog-section.sh` and `release-notes.sh` (release notes), `release-assets.sh` (the credential-free files of a GitHub Release), `preview-on-consumer.sh` (an unreleased Platform on a real consumer) and `canary.sh` (that preview on every consumer, which `release.sh` requires), `new-consumer.sh` (a new repository rendered from the canon, `--frontend next` included), `adr-index.sh` (the ADR index), `check-doc-links.py` (offline link and anchor check of the Markdown), `canon-diff.py` (the consumer impact of a pull request, run by `consumer-impact.yml`, on the engine the bump's `--report` shares), `ring-rollout.sh` (the maintainer's Touchstone-first bump of every consumer), `verify-consumable.sh` (the release resolves as a consumer resolves it), `canon-package-json.mjs` (canon CVE scan), and the maintainer's `consumer-audit.sh`, `repo-settings.sh` (GitHub settings as code, with `.github/rulesets/`) and `write-verification-metadata.sh` (Gradle dependency verification of Platform's modules) | not published |

*Incubating* artifacts are published and versioned with everything else, but no product
repository has adopted them yet. Treat their API as provisional until the first one does: that
repository's adoption pull request removes the label here.

Every published artifact, with its exact coordinates, and how a release reaches each registry are
described in [RELEASING.md](RELEASING.md).

## Consumers

| Repository | Layout |
|---|---|
| `DominikSienkiewicz/Azimuth` | backend and frontend |
| `DominikSienkiewicz/Touchstone` | multi-module backend, no frontend |
| `DominikSienkiewicz/Training` | backend and frontend |

The list is [`scripts/consumers.txt`](scripts/consumers.txt), which
`scripts/consumer-audit.sh` reads: it prints each repository's Platform pin, Gradle wrapper, runtime
image, Platform artifacts, npm pins, workflow references and `platform-bump.yml` caller, with GET requests
only. Its output describes private repositories, so it runs on the maintainer's machine, not in CI.

### Reusable workflows

Consumers call them as `uses: DominikSienkiewicz/Platform/.github/workflows/<name>.yml@vX.Y.Z`, with
the tag of their Platform pin. Triggers are declared by the calling workflow; the platform keeps only
the logic. What each caller must grant and pass, with a snippet per workflow, is in
[docs/reusable-workflows.md](docs/reusable-workflows.md).

| Workflow | What it does |
|---|---|
| `backend-ci.yml` | runs the Gradle tasks of a Spring backend (default `build`) on the platform toolchain |
| `frontend-ci.yml` | installs, lints, type-checks, tests and builds a frontend; `strict: true` makes every standard script and the `platform-versions-check` guard mandatory, and checks the OpenAPI types of a repository that configures `platform.openapi` |
| `api-contract.yml` | fails a pull request that breaks the committed OpenAPI spec (oasdiff), unless it carries the `api-breaking` label; see [docs/api-contracts.md](docs/api-contracts.md) |
| `scorecard.yml` | OpenSSF Scorecard |
| `security-scan.yml` | dependency CVE scan: CycloneDX SBOM + Grype for the backend, `package-lock.json` for the frontend; CRITICAL and HIGH fail the build |
| `semgrep.yml` | Semgrep SAST over the source code |
| `container-scan.yml` | scans published images: Grype is the gate, Snyk a non-blocking second opinion |
| `deploy.yml` | builds and pushes images to GHCR; with `scan-images`, gates them by digest with Grype and Trivy and signs them with cosign keyless only after both pass; it deploys nothing, `promote.yml` calls it |
| `promote.yml` | builds and pushes the images through `deploy.yml` without SSH, gates them with Grype and Trivy and signs them keyless (one image with `single-image`), then commits the new image tags to a GitOps repository with a GitHub App token, for a cluster that Argo CD syncs |
| `platform-bump.yml` | bumps the repository to a Platform release and opens a pull request with the diff, release notes and consumer actions |

### Convention plugins

| Plugin | What it brings |
|---|---|
| `seniordev.settings-conventions` | applied in `settings.gradle.kts`: the Foojay toolchain resolver and the dependency repositories (an optional `platformRepository`, Maven Central, GitHub Packages) |
| `seniordev.java-conventions` | toolchain 27, Spotless (Google Java Format), Checkstyle (`maxWarnings=0`), JaCoCo with coverage summed across `test` **and** `integrationTest`, a configurable coverage threshold (`coverageMinimum`, default 0.00), and the dependency version and runtime image gates |
| `seniordev.quality-conventions` | PIT (mutation testing), SpotBugs (report-only, see [ADR-0005](docs/adr/0005-spotbugs-report-only.md)), CycloneDX (SBOM), SonarQube Cloud from the root of a single-module build |
| `seniordev.sonar-conventions` | the root of a multi-module build: one SonarQube Cloud analysis that collects the JaCoCo report of every module |
| `seniordev.nullness-conventions` | opt-in: Error Prone with NullAway in JSpecify mode, failing `compileJava` on a null dereference in packages marked `@NullMarked` |
| `seniordev.spring-modulith-conventions` | `platform-bom` (Boot / Modulith / Spring AI / JUnit BOMs with the CVE floors and the JDK 27 overrides), shared test dependencies (Modulith-test, Testcontainers, ArchUnit), and a unit ‖ integration ‖ model test taxonomy |

Every task, property and default they add is listed in [docs/reference.md](docs/reference.md).

## How it fits together

```mermaid
flowchart LR
  release["./release.sh"] -->|annotated tag| tag(("vX.Y.Z"))
  tag --> workflow["release.yml<br/>after green ci.yml"]
  workflow --> maven[("GitHub Packages Maven<br/>plugins, catalog, BOM,<br/>test-fixtures, observability-starter")]
  workflow --> npm[("GitHub Packages npm<br/>@dominiksienkiewicz/*")]
  workflow --> notes["GitHub Release<br/>CHANGELOG section"]

  preset["default.json<br/>on main"]

  subgraph consumer["Consumer repository"]
    gradlePins["gradle.properties<br/>platformVersion"]
    npmPins["frontend/package.json<br/>exact pins from versions.json"]
    callers[".github/workflows<br/>uses: …@vX.Y.Z"]
    renovate["renovate.json<br/>extends"]
  end

  maven -->|pinned| gradlePins
  npm -->|pinned| npmPins
  tag -->|pinned| callers
  preset -.->|floating| renovate
  bump["scripts/platform-bump.sh"] -->|bumps| gradlePins
  bump -->|bumps| npmPins
```

Three channels are pinned to one release: the Gradle plugins and catalog, the npm packages and the
reusable workflows. `platform-bump` moves all three and prints the notes of every release it
crosses. One reference floats: the
Renovate preset is read from `main` on every Renovate run. There is no floating workflow tag: a caller
pins the exact tag ([ADR-0002](docs/adr/0002-release-and-versioning-contract.md)).

## Reference consumers

[`templates/jvm/`](templates/jvm/) contains a pure Java library and a minimal Spring
application. Gradle TestKit consumes locally published plugins and catalog artifacts
using these templates. Main CI includes all five published Maven modules of `gradle/maven-modules.txt`.
Consumers can opt into mandatory frontend checks with `strict: true`.

Platform's own Java modules, `test-fixtures` and `observability-starter`, apply `seniordev.java-conventions`
and `seniordev.quality-conventions` from `gradle/build-logic` through `includeBuild`, so the code shipped
to consumers passes the same Spotless, Checkstyle, coverage, `platformDependencyCheck` and SpotBugs gates;
they compile to the same Java 27 bytecode as consumers' code.

### The starter's modules

The Spring starter, [`templates/jvm/spring-app`](templates/jvm/spring-app/), has two Spring Modulith
modules: `accounts` publishes `AccountOpened`, and `notifications` listens to it. A consumer gets this
diagram from `AbstractModulithDocumentationTest`, as `build/spring-modulith-docs/modules.mmd` next to the
PlantUML. A unit test of `platform-test-fixtures` compiles the starter, renders its modules the same way and
fails when they differ from [`docs/diagrams/spring-app-modules.mmd`](docs/diagrams/spring-app-modules.mmd);
`scripts/docs-gen.sh` keeps the block below equal to that file.

<!-- include: docs/diagrams/spring-app-modules.mmd -->
```mermaid
flowchart LR
    module_accounts["Accounts"]
    module_notifications["Notifications"]
    module_notifications -->|listens to| module_accounts
```

### Try it without credentials

GitHub Packages refuses anonymous reads, so resolving Platform from it needs a token even though the
repository is public. Every GitHub Release from 1.6.0 on therefore carries the release as files:
`platform-maven-repo-X.Y.Z.zip` (a Maven repository with every module of `gradle/maven-modules.txt`), the npm tarballs and
`SHA256SUMS`, all attested. Build a starter from them without a token:

```bash
gh release download vX.Y.Z --repo DominikSienkiewicz/Platform --pattern 'platform-maven-repo-*.zip' --pattern SHA256SUMS
```

```bash
sha256sum --check --ignore-missing SHA256SUMS && unzip -q platform-maven-repo-X.Y.Z.zip
```

```bash
cp -R templates/jvm/java-library /tmp/try-platform && sed -i.bak 's/^platformVersion=.*/platformVersion=X.Y.Z/' /tmp/try-platform/gradle.properties
```

```bash
(cd /tmp/try-platform && ./gradlew build -PplatformRepository="file://$PWD/platform-maven-repo")
```

`release.yml` proves this on every release: its `verify-bundle` job builds the `spring-app` starter from the
zip alone, with an empty Gradle home and no `GITHUB_TOKEN`.

## Documentation

- **A reviewer's tour, incident notes and how agents build it** → [docs/tour.md](docs/tour.md),
  [docs/notes/](docs/notes/), [docs/engineering-with-agents.md](docs/engineering-with-agents.md).
- **Guidance for coding agents** → [AGENTS.md](AGENTS.md) for this repository, the
  [rule sheet](docs/consumer-agents.md) and the [runbooks](docs/runbooks/README.md) for consumer repositories.
- **Consuming the platform in a product repository** → **[docs/consuming.md](docs/consuming.md)** —
  the Gradle `settings.gradle.kts` and `build.gradle.kts` wiring, and the frontend
  `tsconfig` / ESLint / Tailwind / Vitest setup.
- **Every task, property and default the plugins add** → **[docs/reference.md](docs/reference.md)** —
  with the observability starter properties and the test fixtures.
- **Building and publishing locally** → **[docs/local-development.md](docs/local-development.md)** —
  bootstrap, GitHub Packages credentials, and how a local build works without GitHub.
- **Where versions are declared** → **[docs/versions.md](docs/versions.md)** — the single
  source of truth, the versions the convention plugins take from it, and dependency locking.
- **Which Java, Gradle, Spring and Node each release brings** →
  **[docs/compatibility.md](docs/compatibility.md)**.
- **Releasing a new version** → **[RELEASING.md](RELEASING.md)** — what a release publishes,
  idempotency per registry, and how consumers adopt the new version.
- **What changed and what consumers must do** → **[CHANGELOG.md](CHANGELOG.md)**.
- **Canonical files to copy into a repository** → [templates/README.md](templates/README.md).
- **Design decisions** → [`docs/adr/`](docs/adr/), including the
  [release and versioning contract](docs/adr/0002-release-and-versioning-contract.md).
- **What the security scans gate, how to accept a finding and how images are signed** →
  [docs/security-scanning.md](docs/security-scanning.md).
- **Contributing** → [CONTRIBUTING.md](CONTRIBUTING.md) and the [code of conduct](CODE_OF_CONDUCT.md).
- **Reporting a vulnerability** → [SECURITY.md](SECURITY.md).
- **How Platform measures against the OpenSSF Best Practices criteria** →
  [docs/openssf-best-practices.md](docs/openssf-best-practices.md).

### Documentation language

Everything a consumer or an outside reader sees is in English: this README, `docs/**`, RELEASING.md,
the `templates/**` READMEs, the pull request templates, package descriptions, workflow
input descriptions and the messages of every gate. Polish appears only in CLAUDE.md and in code and
workflow comments, which are written for the maintainer.

## Requirements

JDK 27, one JDK for everything ([ADR-0034](docs/adr/0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md)):
it runs the Gradle daemon, builds `build-logic` (Java 26 bytecode until the Kotlin embedded in Gradle can target 27)
and compiles Platform's Java modules and consumers on toolchain 27. The JVM starters carry daemon JVM criteria, so their wrapper starts from any JDK and
Gradle selects or downloads Java 27; Foojay provisions the toolchain locally when it is not installed, and the
reusable CI workflows install it with `setup-java` instead ([`docs/versions.md`](docs/versions.md)). The backend
runtime image is `sapmachine:27-jre`.
Consumers run Gradle 9.8.1 or newer, the first Gradle that starts on JDK 27 (9.6.1 stops with Groovy's
"Unsupported class file major version 71"): TestKit builds a consumer on that minimum. Platform's own wrappers run
the catalog's version, 9.8.2, and `platform-bump` moves an older consumer wrapper up to it, never a newer one down.
Node.js ≥ 22.13 (built with Node 24) and pnpm 11.18.0 for the frontend packages, which declare the
Node range in `engines`; CI runs the frontend workspace on both Node 22.13.0 and 24. Earlier releases
are in the [compatibility matrix](docs/compatibility.md). Every Monday `upstream-canary.yml` builds a
starter on the current Gradle release candidate and watches for an `eclipse-temurin` image of the
toolchain; each finding opens or updates one issue, and its next-JDK leg builds the starter on an early-access
toolchain and fails when a tool cannot read its bytecode, report-only SpotBugs included. The catalog pins
JaCoCo 0.8.16 (Java 27 support and experimental Java 28 support) and SpotBugs 4.10.5 (ASM 9.11).
`PlatformJava28AnalyzerFunctionalTest` checks instrumentation and analysis of class-file major 72 on
the regular JDK 27 test host; the canary checks the actual early-access toolchain. After every push to `main`,
`release-draft.yml` keeps the draft release **Next** current.

## License

[MIT](LICENSE) — Copyright (c) 2026 Dominik Sienkiewicz.

The licence is also declared in the POM metadata of every published Maven artifact (every module of
`gradle/maven-modules.txt`) and in the `license` field of every npm
package, so a consumer's dependency scanner sees it without reading this repository.
