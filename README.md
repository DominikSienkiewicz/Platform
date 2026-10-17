# Platform

[![CI](https://github.com/DominikSienkiewicz/Platform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DominikSienkiewicz/Platform/actions/workflows/ci.yml)
[![Latest version](https://img.shields.io/github/v/tag/DominikSienkiewicz/Platform?filter=v*.*.*&sort=semver&label=version)](https://github.com/DominikSienkiewicz/Platform/tags)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Designed and maintained by [Dominik](https://www.linkedin.com/in/dominik-sienkiewicz/), built with AI coding agents:** I set the architecture, write the specifications, define the quality gates enforced in CI and review every change.

A shared build platform for a multi-repository JVM and frontend organisation. Build
configuration, quality gates, dependency versions and frontend presets live here once,
are published as versioned artifacts, and are consumed like any other dependency.

> Registry: **GitHub Packages** (Maven + npm). Frontend workspaces: **pnpm**.

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

## What it publishes

| Path | Artifact | Published to |
|---|---|---|
| `gradle/build-logic/` | four convention plugins (`seniordev.*-conventions`, including settings) | GitHub Packages (Maven) |
| `gradle/catalog/` | version catalog (`pl.seniordeveloper:platform-catalog`); its bundles `modulith-web`, `modulith-web-tests` and `dev-docker-compose` are *incubating* | GitHub Packages (Maven) |
| `gradle/security-starter/` | `pl.seniordeveloper:platform-security-starter` — configurable SecurityFilterChain and CORS (*incubating*) | GitHub Packages (Maven) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers, test databases) | GitHub Packages (Maven) |
| `frontend/packages/tsconfig/` | `@dominiksienkiewicz/tsconfig` | GitHub Packages (npm) |
| `frontend/packages/eslint-config/` | `@dominiksienkiewicz/eslint-config` | GitHub Packages (npm) |
| `frontend/packages/tailwind-preset/` | `@dominiksienkiewicz/tailwind-preset` (CSS-first `@theme`) | GitHub Packages (npm) |
| `frontend/packages/vitest-config/` | `@dominiksienkiewicz/vitest-config` (jsdom + Testing Library) | GitHub Packages (npm) |
| `frontend/packages/versions/` | `@dominiksienkiewicz/versions` — the frontend version canon, the `platform-versions-check` guard that `frontend-ci` runs in strict mode, and the `platform-bump` bin | GitHub Packages (npm) |
| `frontend/packages/api-client/` | `@dominiksienkiewicz/api-client` — shared `fetch` wrapper (*incubating*) | GitHub Packages (npm) |
| `frontend/packages/query/` | `@dominiksienkiewicz/query` — shared TanStack `QueryClient` and provider (*incubating*) | GitHub Packages (npm) |
| `frontend/packages/ui-registry/` | `@dominiksienkiewicz/ui` — private shadcn registry (*incubating*) | GitHub Packages + HTTP JSON |
| `infra/` | `docker-compose` template (pgvector, optionally Ollama) | copied / submodule |
| `.github/workflows/` | nine reusable workflows, listed [below](#reusable-workflows) | called as `uses: …@v1` |
| `default.json` | shared Renovate preset | `extends: github>DominikSienkiewicz/Platform` |
| `templates/` | canonical `.editorconfig`, `.gitignore`, `Dockerfile.backend` | copied (manual sync) |

*Incubating* artifacts are published and versioned with everything else, but no product
repository has adopted them yet. Treat their API as provisional until the first one does.

Every published artifact, with its exact coordinates, and how a release reaches each registry are
described in [RELEASING.md](RELEASING.md).

### Reusable workflows

Consumers call them as `uses: DominikSienkiewicz/Platform/.github/workflows/<name>.yml@v1`.
Triggers and permissions are declared by the calling workflow; the platform keeps only the logic.

| Workflow | What it does |
|---|---|
| `backend-ci.yml` | runs the Gradle tasks of a Spring backend (default `build`) on the platform toolchain |
| `frontend-ci.yml` | installs, lints, type-checks, tests and builds a frontend; `strict: true` makes every standard script and the `platform-versions-check` guard mandatory |
| `sonar.yml` | SonarQube Cloud analysis for a backend + frontend monorepo |
| `scorecard.yml` | OpenSSF Scorecard |
| `security-scan.yml` | dependency CVE scan: CycloneDX SBOM + Grype for the backend, `package-lock.json` for the frontend; CRITICAL and HIGH fail the build |
| `semgrep.yml` | Semgrep SAST over the source code |
| `container-scan.yml` | scans published images: Grype is the gate, Snyk a non-blocking second opinion |
| `deploy.yml` | builds and pushes images to GHCR, then deploys over SSH with [`scripts/deploy-remote.sh`](scripts/deploy-remote.sh) |
| `roadmap-unblock.yml` | moves roadmap items to ready once their last prerequisite issue is closed |

### Convention plugins

| Plugin | What it brings |
|---|---|
| `seniordev.java-conventions` | toolchain 27, Spotless (Google Java Format), Checkstyle (`maxWarnings=0`), JaCoCo with coverage summed across `test` **and** `integrationTest`, and a ratcheting gate |
| `seniordev.quality-conventions` | PIT (mutation testing), SpotBugs (report-only until it reads Java 27 class files, major version 71), CycloneDX (SBOM) |
| `seniordev.spring-modulith-conventions` | Boot / Modulith / Spring AI BOMs (GA) with CVE and JDK 27 (Lombok, runtime ArchUnit) version overrides, shared test dependencies (Modulith-test, Testcontainers, ArchUnit), enforced `junit-bom`, and a unit ‖ integration test taxonomy |

## Reference consumers

[`templates/jvm/`](templates/jvm/) contains a pure Java library and a minimal Spring
application. Gradle TestKit consumes locally published plugins and catalog artifacts
using these templates. Main CI includes all four published Maven modules; a failed
UI registry build blocks npm publication. Consumers can opt into mandatory frontend
checks with `strict: true`.

## Documentation

- **Consuming the platform in a product repository** → **[docs/consuming.md](docs/consuming.md)** —
  the Gradle `settings.gradle.kts` and `build.gradle.kts` wiring, and the frontend
  `tsconfig` / ESLint / Tailwind / Vitest setup.
- **Building and publishing locally** → **[docs/local-development.md](docs/local-development.md)** —
  bootstrap, GitHub Packages credentials, and how a local build works without GitHub.
- **Where versions are declared** → **[docs/versions.md](docs/versions.md)** — the single
  source of truth, the one remaining duplication, and dependency locking.
- **Releasing a new version** → **[RELEASING.md](RELEASING.md)** — what a release publishes,
  idempotency per registry, and how consumers adopt the new version.
- **Design decisions** → [`docs/adr/`](docs/adr/).
- **Reporting a vulnerability** → [SECURITY.md](SECURITY.md).

## Requirements

JDK 25 or newer to run Gradle: `build-logic`, `test-fixtures` and `security-starter` compile
to Java 25 bytecode. Consumers compile on toolchain 27, which Foojay provisions locally when it
is not installed; the reusable CI workflows install it with `setup-java` instead
([`docs/versions.md`](docs/versions.md)). The backend runtime image is `sapmachine:27-jre`.
Node.js ≥ 22.13 (built with Node 24) and pnpm 11.18.0 for the frontend packages.

## License

[MIT](LICENSE) — Copyright (c) 2026 Dominik Sienkiewicz.

The licence is also declared in the POM metadata of every published artifact (`catalog`,
`build-logic`, `test-fixtures`, `security-starter`), so a consumer's dependency scanner
sees it without reading this repository.
