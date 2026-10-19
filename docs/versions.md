# Where versions are declared

`gradle/catalog/libs.versions.toml` is the only place a library or plugin version is
declared. `gradle/build-logic` includes **that same file** through its own
`settings.gradle.kts`:

```kotlin
versionCatalogs { create("libs") { from(files("../catalog/libs.versions.toml")) } }
```

It reads the file rather than the published artifact because `platform-catalog` does not
yet exist at the time `build-logic` is compiled. The plugin marker artifacts on the
`build-logic` classpath therefore take their versions straight from the canonical file.

## Why a version catalog and not a java-platform BOM

Platform publishes its versions as a version catalog (`pl.seniordeveloper:platform-catalog`) and no
`java-platform` BOM. That is a choice, not an omission:

- The Spring Boot, Spring Modulith and Spring AI BOMs already align the transitive versions of every
  Spring consumer: `seniordev.spring-modulith-conventions` imports them through
  `io.spring.dependency-management`, and Platform overrides them only as ADR-0008 allows.
- `platformDependencyCheck` governs declared versions and fails on drift. An `enforcedPlatform` BOM
  would instead override a drifted version silently, so the consumer would never learn that its build
  file disagrees with the canon.
- A second version mechanism next to `io.spring.dependency-management` makes precedence hard to read:
  which of a BOM constraint, a dependency-management import and a catalog version wins depends on
  plugin internals.
- Revisit when a consumer without Spring needs transitive alignment. Generate that BOM from
  `gradle/catalog/libs.versions.toml` then, so that the catalog stays the single source of every
  version (hard rule 1).

## Mirrored literals

A precompiled script plugin does not read a version catalog at compile time, so some
versions are literals in the **sources** of the convention plugins and entries in the
catalog at the same time. Bumping one of them means editing both places, and a test in
`build-logic` fails when the two drift. Drift of a BOM import would otherwise be silent for
consumers: `platformDependencyCheck` does not see `mavenBom(...)` imports, so their runtime
would stay on the old BOM, CVE fixes included.

| Mirrored literal | Source | Catalog key | Guarded by |
|---|---|---|---|
| `googleJavaFormat("…")` | `seniordev.java-conventions` | `googleJavaFormat` | `PlatformToolVersionMirrorTest` |
| `JavaLanguageVersion.of(…)` | `seniordev.java-conventions` | `java` | `PlatformToolVersionMirrorTest` |
| checkstyle `toolVersion` | `seniordev.java-conventions` | `checkstyle` | `PlatformCatalogMirrorTest` |
| jacoco `toolVersion` | `seniordev.java-conventions` | `jacoco` | `PlatformCatalogMirrorTest` |
| spotbugs `toolVersion` | `seniordev.quality-conventions` | `spotbugs` | `PlatformCatalogMirrorTest` |
| `pitestVersion` | `seniordev.quality-conventions` | `pitestTool` | `PlatformToolVersionMirrorTest` |
| `junit5PluginVersion` | `seniordev.quality-conventions` | `pitestJunit5` | `PlatformCatalogMirrorTest` |
| `springBootVersion` | `seniordev.spring-modulith-conventions` | `springBoot` | `PlatformCatalogMirrorTest` |
| `springModulithVersion` | `seniordev.spring-modulith-conventions` | `springModulith` | `PlatformCatalogMirrorTest` |
| `springAiVersion` | `seniordev.spring-modulith-conventions` | `springAi` | `PlatformCatalogMirrorTest` |
| `junitVersion` | `seniordev.spring-modulith-conventions` | `junit` | `PlatformCatalogMirrorTest` |
| `archunitVersion` | `seniordev.spring-modulith-conventions` | `archunit` | `PlatformToolVersionMirrorTest` |
| `ext["lombok.version"]` | `seniordev.spring-modulith-conventions` | `lombok` | `PlatformToolVersionMirrorTest` |
| `ext["tomcat.version"]` | `seniordev.spring-modulith-conventions` | `tomcat` | `PlatformCveOverrideMirrorTest` |
| `ext["jackson-bom.version"]` | `seniordev.spring-modulith-conventions` | `jacksonBom` | `PlatformCveOverrideMirrorTest` |
| `ext["jackson-2-bom.version"]` | `seniordev.spring-modulith-conventions` | `jackson2Bom` | `PlatformCveOverrideMirrorTest` |
| `toolchain-java-version` default | `backend-ci.yml`, `deploy.yml`, `sonar.yml` | `java` | `PlatformToolVersionMirrorTest` |

`pitestTool` is the PIT engine and `pitest` the Gradle plugin; in the same way `spotbugs` is
the SpotBugs engine and `spotbugsPlugin` the Gradle plugin. The formatter version is pinned
rather than left to Spotless because Spotless picks its default from the JVM that runs
Gradle, and on JDK 27 it picked a release that crashes on the new javac.

## Overrides above the Spring Boot BOM

Boot 4.1.1 manages Netty 4.2.17.Final and PostgreSQL 42.7.13, so the previous
`netty.version` and `postgresql.version` overrides have been removed. Keeping them
would force versions older than the BOM. The `lombok.version` override remains at
`1.18.48`: the BOM still pins 1.18.46, incompatible with javac 27.

Three CVE overrides came back after the first canon scan, because no Boot release newer than
4.1.1 exists yet and its BOM manages vulnerable versions:

| Property | Boot 4.1.1 | Override | Why |
|---|---|---|---|
| `tomcat.version` | 11.0.24 | 11.0.27 | three CRITICAL advisories (GHSA-9xv2-5v5q-p794, GHSA-gcx9-497g-6cp6, GHSA-h3x4-894j-xpx5), fixed in 11.0.25 |
| `jackson-bom.version` | 3.1.5 | 3.1.8 | HIGH advisories in jackson-core and jackson-databind, fixed in 3.1.7 |
| `jackson-2-bom.version` | 2.21.5 | 2.21.8 | the same advisories in the 2.x line, fixed in 2.21.7 |

Each takes the newest patch of the line Boot manages, not a newer minor. Remove an override as soon
as a Boot release manages a fixed version; `canon-cve-scan.yml` shows whether that release is clean.

ArchUnit is overridden differently, because no BOM manages it and so there is no property to set:
`spring-modulith-core` 2.1.1 declares ArchUnit `1.4.2` as a compile dependency, and that version cannot
read class-file major 71 (javac 27). Spring Modulith builds `ApplicationModules` at application start,
so on the runtime classpath it imports no classes and the context fails with "No classes found in
packages". Tests never saw it, because `archunit-junit5` pulls the catalog version onto the test
classpaths only. The convention therefore declares `com.tngtech.archunit:archunit` in
`dependencyManagement.dependencies` at `archunitVersion` (catalog `archunit`), which applies to every
configuration, transitive dependencies included. Drop it once `spring-modulith-core` itself depends on
an ArchUnit that reads Java 27 class files (1.5.0 or later). `PlatformToolVersionMirrorTest` guards
both the version mirror and the presence of this managed dependency.

Consumers
that lock dependencies must regenerate `gradle.lockfile` and `gradle/verification-metadata.xml`
after taking a platform version that changes an override.

## CVE response

Consumers cannot fix a vulnerable version the platform manages: the version guards reject any other
version of a canon dependency, and a BOM-managed library follows the BOM Platform imports. A known CVE
in the canon is therefore Platform's to fix, with a patch release.

[`canon-cve-scan.yml`](../.github/workflows/canon-cve-scan.yml) scans what the platform imposes: a
lockfile resolved from `versions.json`, and the CycloneDX SBOM of `gradle/canon-probe`, a consumer that
applies the convention plugins from source and declares every catalog library. It runs every Monday
at 04:00 UTC, before the consumers' weekly scans, and on every push to `main` that changes the canon.
Grype fails it on a HIGH or CRITICAL finding that has a fix. It is advisory and does not gate releases.
`workflow_dispatch` with `ref=vX.Y.Z` scans the canon of an older release, for example to tell a
consumer which releases are affected.

When it is red, the maintainer:

1. bumps the canon entry or the catalog version, or, for a library the Spring Boot BOM manages, adds
   a CVE override in `seniordev.spring-modulith-conventions` (see
   [Overrides above the Spring Boot BOM](#overrides-above-the-spring-boot-bom)) until a Boot release
   manages a fixed version;
2. ships a patch release within seven days of the finding, three for a CRITICAL one;
3. or, when no fix can be adopted yet, accepts the finding in Platform's own `.grype.yaml`, with an
   expiry as described in [security-scanning.md](security-scanning.md), so that the scan is green again.

## What platformDependencyCheck does not see

`platformDependencyCheck` compares the versions a build *declares* with the catalog. A consumer can
still move a version through channels the check cannot see:

| Channel | Example | What reports it |
|---|---|---|
| A BOM version property | `extra["jackson-bom.version"] = "3.1.4"`, or `jackson-bom.version=` in `gradle.properties` | `platformBomOverrideCheck` on `check`, as a warning (Decision 18); Platform's own overrides are not reported |
| A resolution rule | `resolutionStrategy.eachDependency { useVersion("42.7.12") }` | `platform-bump`, which lists each one with its file and line |
| A forced or strict version | `force("…")`, `strictly("…")` | `platform-bump`, the same way |

Resolution rules cannot be detected from the build model, because dependency-management itself is
built on `eachDependency`. A rule beats the BOM, so after a bump it can pin a version older than the
one the new BOMs manage. Remove an override as soon as the Platform BOMs manage an equal or higher
version; move one that must stay into `seniordev.spring-modulith-conventions`, so every consumer gets it.

## Runtime image for the JDK 27 toolchain

Bytecode 27 needs a runtime of at least 27, and the consumers' images derive from
`templates/Dockerfile.backend`, so the toolchain and the runtime image move together.
`platformRuntimeImageCheck` in `seniordev.java-conventions` enforces it in every consumer's
`check`: the final `FROM` of the Dockerfile must not run an older Java than the toolchain.

On 2026-09-25 the toolchain 27 entry condition was met with `sapmachine:27-jre`, not
`eclipse-temurin:27-jre`: ten days after the JDK 27 GA, Docker Hub still had no Temurin 27
image. SapMachine is an official Docker Hub image (SAP's OpenJDK build) based on Ubuntu 24.04, and it runs the template unchanged: `groupadd`/`useradd`, `bash` and `sh` are
present, `/usr/bin/pebble` is not. At the switch neither image carried a Critical or High
vulnerability (Docker Scout, `linux/amd64`); SapMachine carried 34 Medium and 2 Low, Temurin 26
none, because its base is the older Ubuntu LTS.

Move back to `eclipse-temurin:27-jre` when that tag exists and a Grype scan of it passes the
`container-scan.yml` gate (`high`, `only-fixed`). Change only the `FROM` line; the rest of the
template is image-neutral.

## Frontend runtime image

`templates/Dockerfile.frontend` runs Next.js standalone on `node:24-slim`, the Node major of
`frontend/.nvmrc`. Slim (Debian, glibc) rather than alpine (musl): `npm ci --ignore-scripts` installs
the prebuilt glibc binaries of `sharp` and other native packages as optionalDependencies, exactly as on
the Ubuntu CI runners, so the image runs the dependency tree CI tested. The token reaches only the
`npm ci` step, as the BuildKit secret `github_token`; `templates/tests/dockerfile-frontend.test.sh`
pins all of it.

## JDK 27 toolchain on CI

The reusable `backend-ci.yml`, `deploy.yml` and `sonar.yml` install the toolchain JDK with
`actions/setup-java` (input `toolchain-java-version`, default `27`) and register it through
`org.gradle.java.installations.paths` in the Gradle user home. Gradle itself still runs on
the `java-version` JDK (25), because `build-logic` is compiled to Java 25 bytecode.

Foojay is bypassed on CI on purpose. On 2026-09-25 it indexed Temurin 27 for Linux only as the
Alpine (musl) build; the resolver prefers Temurin, picked that archive on the glibc runner and
Gradle rejected it ("Unpacked JDK archive does not contain a Java home"). `setup-java` reads the
Adoptium API directly and gets the glibc build. The `toolchain-java-version` default mirrors
the catalog `java` entry; `PlatformToolVersionMirrorTest` fails when it drifts in any workflow
under `.github/workflows/`, or when one of the three workflows loses the input. `security-scan.yml` runs only `cyclonedxBom`, which does not
compile, and keeps a single JDK.

## Dependency locking

`gradle/build-logic`, `gradle/test-fixtures` and `gradle/security-starter` each carry a
`gradle.lockfile` for reproducible resolution. After bumping any version in those modules,
regenerate the lockfile and commit the diff:

```bash
cd gradle/<module> && ./gradlew dependencies --write-locks
```

`gradle/catalog` keeps an **empty, hand-written** lockfile. A `version-catalog` module has
no resolvable configuration, so `--write-locks` succeeds without creating a file. The file
exists so that every Gradle module in the repository has one — there is nothing to lock, so
do not try to regenerate it.

## Dependency verification

The same three modules carry `gradle/verification-metadata.xml` with the SHA-256 of every artifact and
metadata file they resolve, the standard the consumers' `backend/gradle/verification-metadata.xml`
already meets. A lockfile pins versions; this file pins content, so an artifact replaced under the same
version in a repository or on the network fails the build instead of reaching the published plugins.
Gradle verifies strictly whenever the file exists, locally and in CI.

After any change that resolves something new (a catalog bump, a new library, a plugin update), regenerate
the files and review the diff:

```bash
scripts/write-verification-metadata.sh
```

It runs two passes per module with `--refresh-dependencies`, as `platform-bump` does for consumers:
`build` (in build-logic without the TestKit suite), then `dependencies`. A Renovate pull request that
bumps the catalog stays red on verification until you run the script and push its result to that branch.
`gradle/catalog` has no file: it resolves nothing, as its empty lockfile shows. `test-fixtures` and
`security-starter` include `gradle/build-logic` for their convention plugin, and in a composite build the
root's file verifies everything, so their files also hold the checksums of the plugin classpath.

## Gradle wrapper

Every Gradle module carries the same wrapper. `gradle-wrapper.properties` pins the distribution
with `distributionSha256Sum`, and the `wrapper-validation` job in `ci.yml` checks every
`gradle-wrapper.jar` against the checksums Gradle publishes; `setup-gradle` repeats that check in
each workflow that builds. A new module copies the wrapper of an existing one.

The catalog entry `gradle` is the version of those wrappers, and `PlatformGradleVersionMirrorTest`
fails when a wrapper or the `gradle-version` of `canon-cve-scan.yml` differs from it. `platform-bump`
reads the entry from the catalog of the target release and moves the consumer's wrapper to it, with
the distribution's SHA-256.

A consumer may run an older Gradle than Platform does, down to `minimumConsumerGradle` in
`gradle/build-logic/gradle.properties` (9.6.1). `PlatformMinimumGradleFunctionalTest` builds a
consumer on that version, and `seniordev.settings-conventions` fails an older build with a message
that names the fix. Raising the minimum is a consumer action: a MINOR release with a CHANGELOG entry.

## Verification gate for the toolchain

Gradle's Java 27 support does not establish compatibility for every analyzer or framework;
the consumer TestKit suite in `build-logic` is the verification gate. It runs the consumer
`build` with SpotBugs, JaCoCo, PIT and CycloneDX on class-file 71, fails on "Unsupported class
file major version", and starts the packaged Spring `bootJar` from its own runtime classpath.
What each release changed is recorded in [CHANGELOG.md](../CHANGELOG.md), not here.

## Frontend canon

`frontend/packages/versions/versions.json` is the frontend counterpart of the catalog: every npm
dependency of a consumer takes its exact version from it, and `platform-versions-check` fails
`frontend-ci` on anything else. Platform's own workspace follows the same rule, so its packages are
tested on the versions consumers run:

- every `dependencies`, `devDependencies` and `optionalDependencies` entry of `frontend/package.json`
  and `frontend/packages/*/package.json` is the canon version;
- `eslint-config`, `prettier-config` and `ui` declare their runtime dependencies and peers at the exact
  canon version;
- the other packages keep peer ranges such as `^4`, which must admit the canon version;
- `react`, `react-dom` and `@types/node` are root devDependencies, because pnpm resolves the peers of
  workspace packages from the root and would otherwise pick versions off the canon.

`frontend/packages/versions/test/self-canon.test.mjs` runs the guard on each of those manifests and
checks the peer ranges. Regenerate `frontend/pnpm-lock.yaml` with `pnpm install` after a canon
bump: CI installs with `--frozen-lockfile`.
