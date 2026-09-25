# Platform

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
| `gradle/build-logic/` | three convention plugins (`seniordev.*-conventions`) | GitHub Packages (Maven) |
| `gradle/catalog/` | version catalog (`pl.seniordeveloper:platform-catalog`) | GitHub Packages (Maven) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` (Testcontainers, test databases) | GitHub Packages (Maven) |
| `frontend/packages/tsconfig/` | `@dominiksienkiewicz/tsconfig` | GitHub Packages (npm) |
| `frontend/packages/eslint-config/` | `@dominiksienkiewicz/eslint-config` | GitHub Packages (npm) |
| `frontend/packages/tailwind-preset/` | `@dominiksienkiewicz/tailwind-preset` (CSS-first `@theme`) | GitHub Packages (npm) |
| `frontend/packages/ui-registry/` | `@dominiksienkiewicz/ui` — private shadcn registry | GitHub Packages + HTTP JSON |
| `frontend/packages/vitest-config/` | `@dominiksienkiewicz/vitest-config` (jsdom + Testing Library) | GitHub Packages (npm) |
| `infra/` | `docker-compose` template (pgvector, optionally Ollama) | copied / submodule |
| `.github/workflows/` | reusable CI (`backend-ci`, `frontend-ci`, `sonar`, `scorecard`) and security (`security-scan` SBOM+Grype, `semgrep` SAST, `container-scan` Grype+Snyk) | called as `uses: …@v1` |
| `default.json` | shared Renovate preset | `extends: github>DominikSienkiewicz/Platform` |
| `templates/` | canonical `.editorconfig`, `.gitignore`, `Dockerfile.backend` | copied (manual sync) |

### Convention plugins

| Plugin | What it brings |
|---|---|
| `seniordev.java-conventions` | toolchain 27, Spotless (Google Java Format), Checkstyle (`maxWarnings=0`), JaCoCo with coverage summed across `test` **and** `integrationTest`, and a ratcheting gate |
| `seniordev.quality-conventions` | PIT (mutation testing), SpotBugs (report-only on JDK 25), CycloneDX (SBOM) |
| `seniordev.spring-modulith-conventions` | Boot / Modulith / Spring AI BOMs (GA) with CVE and JDK 27 (Lombok, runtime ArchUnit) version overrides, shared test dependencies (Modulith-test, Testcontainers, ArchUnit), enforced `junit-bom`, and a unit ‖ integration test taxonomy |

## Documentation

- **Consuming the platform in a product repository** → **[docs/consuming.md](docs/consuming.md)** —
  the Gradle `settings.gradle.kts` and `build.gradle.kts` wiring, and the frontend
  `tsconfig` / ESLint / Tailwind / Vitest setup.
- **Building and publishing locally** → **[docs/local-development.md](docs/local-development.md)** —
  bootstrap, GitHub Packages credentials, and how a local build works without GitHub.
- **Where versions are declared** → **[docs/versions.md](docs/versions.md)** — the single
  source of truth, the one remaining duplication, and dependency locking.
- **Design decisions** → [`docs/adr/`](docs/adr/).

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
