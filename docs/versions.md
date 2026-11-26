# Where versions are declared

`gradle/catalog/libs.versions.toml` is the only place the version of a library or plugin of the Platform frame is
declared ([ADR-0037](adr/0037-platform-governs-the-frame.md)). A library outside the frame belongs to the
consuming application, which registers it in a catalog of its own
([Libraries your application owns](consuming.md#libraries-your-application-owns)). `gradle/build-logic` includes **that same file** through its own
`settings.gradle.kts`:

```kotlin
versionCatalogs { create("libs") { from(files("../catalog/libs.versions.toml")) } }
```

It reads the file rather than the published artifact because `platform-catalog` does not
yet exist at the time `build-logic` is compiled. The plugin marker artifacts on the
`build-logic` classpath therefore take their versions straight from the canonical file.

## Catalog for aliases, BOM for constraints

Platform publishes its versions twice, from one source ([ADR-0013](adr/0013-catalog-for-aliases-bom-for-constraints.md)):

- `pl.seniordeveloper:platform-catalog`, the version catalog, holds the alias and version of every library and
  plugin of the frame. Consumers declare the frame's dependencies through it, and `platformDependencyCheck` holds
  explicit versions of them to it.
- `pl.seniordeveloper:platform-bom`, a `java-platform` built from the same TOML, holds what a catalog
  cannot express: the imports of the Spring Boot, Spring Modulith, Spring AI and JUnit BOMs, the CVE
  floors and compatibility overrides with their `because(...)` reasons (the table in
  [Overrides above the Spring Boot BOM](#overrides-above-the-spring-boot-bom)), and the Platform artifacts.

`platform-test-fixtures`, `platform-observability-starter` and `seniordev.spring-modulith-conventions` import
`platform-bom` of their own release, so the floors live in one place and reach every classpath those
builds resolve. `PlatformBomImportFunctionalTest` holds the conventions to it with `dependencyInsight`:
the BOM's Lombok, Jackson and Tomcat win, also over a consumer's `jackson-bom.version`, because the BOM
imports the fixed Jackson BOMs before Boot ([ADR-0013](adr/0013-catalog-for-aliases-bom-for-constraints.md)).
Consumers delete their own override blocks when they adopt that release. A build without the Spring
conventions takes the same floors with:

```kotlin
dependencies {
    implementation(platform(libs.platform.bom))
}
```

`platformDependencyCheck` still fails on drift instead of letting a BOM override a declared version
silently: the BOM aligns transitive versions, the gate governs declared ones.

## Versions the convention plugins impose

The convention plugins impose some versions on every consumer: the toolchain, the quality tools and
the BOMs they import, and the overrides above the Boot BOM. A precompiled script plugin does not read
a version catalog at compile time, so these used to be literals mirrored in the plugin sources. Now
`build-logic`'s `generatePlatformVersions` task writes them from the catalog into
`PlatformVersions.kt` in the main source set before the plugins compile, so a bump is one catalog entry.
`PlatformVersionsTest` checks that every constant equals its catalog entry and that the convention
sources contain no version literal.

| Constant | Used by | Catalog key |
|---|---|---|
| `JAVA` | `JavaLanguageVersion.of(…)` in `seniordev.java-conventions` | `java` |
| `GOOGLE_JAVA_FORMAT`, `CHECKSTYLE`, `JACOCO` | `seniordev.java-conventions` | `googleJavaFormat`, `checkstyle`, `jacoco` |
| `SPOTBUGS`, `PITEST_TOOL`, `PITEST_JUNIT5` | `seniordev.quality-conventions` | `spotbugs`, `pitestTool`, `pitestJunit5` |
| `PLATFORM` | the `platform-bom` import of `seniordev.spring-modulith-conventions` and the pin check | `platform` (the release) |
| `JUNIT`, `ARCHUNIT` | the JUnit baseline of `seniordev.java-conventions`, the JUnit BOM and ArchUnit of `seniordev.spring-modulith-conventions` | `junit`, `archunit` |
| `ERROR_PRONE`, `NULLAWAY` | the `errorprone` dependencies of `seniordev.nullness-conventions` | `errorprone`, `nullaway` |
| `SPRING_BOOT`, `SPRING_MODULITH`, `SPRING_AI`, `LOMBOK`, `TOMCAT`, `JACKSON_BOM`, `JACKSON_2_BOM` | no convention since the conventions import `platform-bom`; `PlatformVersionsTest` still compares them with the catalog | `springBoot`, `springModulith`, `springAi`, `lombok`, `tomcat`, `jacksonBom`, `jackson2Bom` |

Two mirrors live outside Kotlin and stay guarded by tests: the `toolchain-java-version` default of
`backend-ci.yml`, `deploy.yml` and `platform-bump.yml` (catalog `java`,
`PlatformToolVersionMirrorTest`), and the Gradle wrappers and the minimum consumer Gradle
(`PlatformGradleVersionMirrorTest`).

`pitestTool` is the PIT engine and `pitest` the Gradle plugin; in the same way `spotbugs` is
the SpotBugs engine and `spotbugsPlugin` the Gradle plugin. The formatter version is pinned
rather than left to Spotless because Spotless picks its default from the JVM that runs
Gradle, and on JDK 27 it picked a release that crashes on the new javac.

## Overrides above the Spring Boot BOM

Spring Boot 4.1.3 manages Spring Framework 7.0.11, Spring Security 7.1.3, Netty 4.2.20.Final and Lombok 1.18.48. The jOOQ generator follows Boot's jOOQ version, 3.21.9.

| Component | Boot 4.1.3 | Platform | Reason and removal condition |
|---|---|---|---|
| PostgreSQL JDBC | 42.7.14 | 42.7.15 | The November security release fixes SQL parsing, authentication and TLS issues. Remove when Boot manages 42.7.15 or later. [pgJDBC](https://jdbc.postgresql.org/) |
| Embedded Tomcat | 11.0.27 | 11.0.29 | Retain the fixes for the November advisories across core, EL and WebSocket. Track the separate cluster TLS-PSK fix in 11.0.30. Remove when Boot covers the outstanding fixes. [Apache advisories](https://tomcat.apache.org/security-11.html) |
| Jackson 3 BOM | 3.1.8 | 3.1.9 | Parser limits and polymorphic type handling. Remove when Boot manages 3.1.9 or later. [Release notes](https://github.com/FasterXML/jackson/wiki/Jackson-Release-3.1.9) |
| Jackson 2 BOM | 2.21.8 | 2.21.9 | Corresponding parser and databinding fixes. Remove when Boot manages 2.21.9 or later. [Release notes](https://github.com/FasterXML/jackson/wiki/Jackson-Release-2.21.9) |
| OpenTelemetry Java BOM | 1.62.0 | 1.68.0 | CVE-2026-118259 affects incoming W3C trace state. Align the API, context, SDK and exporters. Remove when Boot manages 1.68.0 or later. [OpenTelemetry advisory](https://github.com/open-telemetry/opentelemetry-java/security/advisories/GHSA-ccrj-gw8r-854m) |
| Logback Classic and Core | 1.5.38 | 1.6.8 | CVE-2026-19880 and CVE-2026-104721 affect sifting appenders that use untrusted MDC values. Remove when Boot manages 1.6.8 or later. [Logback release notes](https://logback.qos.ch/news.html) |

Guava has a separate floor because Boot does not manage it. Platform requires `33.8.0-jre` for
the application BOM and Gradle tooling. Older versions can use excessive CPU when untrusted keys
collide in `HashBiMap` or `LinkedHashMultimap`. Remove a floor when the dependencies that bring
Guava onto that classpath resolve the fixed version themselves. [Guava advisory](https://github.com/google/guava/security/advisories/GHSA-v5x9-67m3-7m56)

On the Gradle plugin classpath, `jackson2Tooling` aligns Jackson 2 at 2.22.4 to fix
CVE-2026-110879 in polymorphic deserialization. Remove this import once CycloneDX and the other
plugins resolve a fixed Jackson version themselves. [Databind advisory](https://github.com/FasterXML/jackson-databind/security/advisories/GHSA-m8xf-2cr7-77ph)

ArchUnit is overridden differently, because no BOM manages it and so there is no property to set:
`spring-modulith-core` 2.1.3 declares ArchUnit `1.4.2` as a compile dependency, and that version cannot
read class-file major 71 (javac 27). Spring Modulith builds `ApplicationModules` at application start,
so on the runtime classpath it imports no classes and the context fails with "No classes found in
packages". Tests never saw it, because `archunit-junit5` pulls the catalog version onto the test
classpaths only. The convention therefore declares `com.tngtech.archunit:archunit` in
`dependencyManagement.dependencies` at `archunitVersion` (catalog `archunit`), which applies to every
configuration, transitive dependencies included. Drop it once `spring-modulith-core` itself depends on
an ArchUnit that reads Java 27 class files (1.5.0 or later). The version comes from `PlatformVersions`,
and `PlatformToolVersionMirrorTest` guards the presence of this managed dependency.

Consumers
that lock dependencies must regenerate `gradle.lockfile` and `gradle/verification-metadata.xml`
after taking a platform version that changes an override.

## CVE response

Consumers cannot fix a vulnerable version the platform manages: the version guards reject any other
version of a canon dependency, and a BOM-managed library follows the BOM Platform imports. A known CVE
in the canon is therefore Platform's to fix, with a patch release. A CVE in a library the application owns
(`appLibs`, or a package in its `package.json`) is fixed in the application: it bumps that version itself.

[`canon-cve-scan.yml`](../.github/workflows/canon-cve-scan.yml) scans what the platform imposes: a
lockfile resolved from `versions.json`, and the CycloneDX SBOM of `gradle/canon-probe`, a consumer that
applies the convention plugins from source and declares every catalog library. Before the probe runs,
the workflow publishes the scanned commit's `platform-bom` to Maven local, and the probe declares it as a
platform, so the SBOM carries the CVE floors a consumer gets; `scripts/check-canon-floors.py` fails the
scan when a checked component in the SBOM falls below its catalog floor. It runs daily
at 04:07 UTC, and on every push to `main` that changes the canon.
Grype fails it on a HIGH or CRITICAL finding that has a fix. It is advisory and does not gate releases.
`workflow_dispatch` with `ref=vX.Y.Z` scans the canon of an older release, for example to tell a
consumer which releases are affected.

When it is red, the maintainer:

1. bumps the canon entry or the catalog version, or, for a library the Spring Boot BOM manages or one
   that even the newest release of a catalog library brings at a vulnerable version, adds
   a CVE floor to the catalog and `platform-bom` (with its key in `scripts/check-canon-floors.py`; see
   [Overrides above the Spring Boot BOM](#overrides-above-the-spring-boot-bom)) until a Boot release
   manages a fixed version;
2. ships a patch release within seven days of the finding, three for a CRITICAL one;
3. or, when no fix can be adopted yet, accepts the finding in Platform's own `.grype.yaml`, with an
   expiry as described in [security-scanning.md](security-scanning.md), so that the scan is green again.

The `CHANGELOG.md` entry of any release that fixes a publicly known vulnerability, a patch or not, names its CVE ids
(the GHSA id when no CVE exists). A consumer then reads from the notes which releases are affected; the OpenSSF
Best Practices criterion `release_notes_vulns` asks for exactly this ([self-assessment](openssf-best-practices.md)).

## What platformDependencyCheck does not see

`platformDependencyCheck` compares the versions a build *declares* for a library of the frame with the canon embedded in the plugin
(`platform-canon.tsv`, generated from `gradle/catalog/libs.versions.toml` when build-logic is built), not with
the consumer's `libs` catalog, which `version(...)` after `from(...)` in `settings.gradle.kts` could override:
such an override is a failure of its own ([PLAT-DEP-004](gates.md#plat-dep-004)), and so is a build without a
`libs` catalog ([PLAT-DEP-005](gates.md#plat-dep-005)). A consumer can still move a version through channels
the check cannot see:

| Channel | Example | What reports it |
|---|---|---|
| A BOM version property | `extra["jackson-bom.version"] = "3.1.4"`, or `jackson-bom.version=` in `gradle.properties` | `platformBomOverrideCheck` on `check`, as a warning (Decision 18); it cannot lower a floor `platform-bom` imports before Boot |
| A resolution rule | `resolutionStrategy.eachDependency { useVersion("42.7.12") }` | `platform-bump`, which lists each one with its file and line |
| A forced or strict version | `force("…")`, `strictly("…")` | `platform-bump`, the same way |
| A BOM-managed library with an explicit version, in a module without `io.spring.dependency-management` | `implementation("io.netty:netty-codec:4.2.0.Final")` in a plain `seniordev.java-conventions` module | Nothing: [PLAT-DEP-003](gates.md#plat-dep-003) sees BOM management only where that plugin is applied; in a Spring application the Boot BOM still aligns the version at runtime |
| A BOM import outside the frame | `implementation(platform("io.netty:netty-bom:4.2.0.Final"))`, `enforcedPlatform(...)` | `platformDependencyCheck`, as a warning ([PLAT-DEP-006](gates.md#plat-dep-006)) |
| A BOM import in the dependency-management DSL | `dependencyManagement { imports { mavenBom("io.netty:netty-bom:4.2.0.Final") } }` | Nothing: PLAT-DEP-006 sees only `platform(...)` and `enforcedPlatform(...)` |

Resolution rules cannot be detected from the build model, because dependency-management itself is
built on `eachDependency`. A rule beats the BOM, so after a bump it can pin a version older than the
one the new BOMs manage. Remove an override as soon as the Platform BOMs manage an equal or higher
version; move one that must stay into `seniordev.spring-modulith-conventions`, so every consumer gets it.

## TypeScript compiler and tooling API

The native TypeScript 7 compiler supplies `tsc` through the exact npm alias
`@typescript/native`. ESLint, Next.js and the OpenAPI generator import the JavaScript compiler API
through `typescript`, which points to the TypeScript 6 compatibility package. Keep both entries
when editing a consumer manifest. Use `npm exec -- tsc --version` to check the native compiler.
[Microsoft's side-by-side configuration](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/#running-side-by-side-with-typescript-60)

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

The reusable `backend-ci.yml` and `deploy.yml` install the toolchain JDK with
`actions/setup-java` (input `toolchain-java-version`, default `27`) and register it through
`org.gradle.java.installations.paths` in the Gradle user home. Gradle itself runs on the
`java-version` JDK, which is the same Java 27 since 1.8.0: Platform builds and tests `build-logic` with Gradle on
JDK 27 and supports no other JDK for Gradle ([ADR-0034](adr/0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md)).
Gradle 9.9.2 embeds Kotlin 2.4.21. Platform targets JVM 26 bytecode for its Kotlin and Java build logic
to preserve compatibility with the minimum consumer Gradle. `templates/tests/jdk-everywhere.test.sh` fails
when any JDK of the workflows, SDKMAN or the starters' daemon criteria leaves the
catalog's `java`.

Foojay is bypassed on CI on purpose. On 2026-09-25 it indexed Temurin 27 for Linux only as the
Alpine (musl) build; the resolver prefers Temurin, picked that archive on the glibc runner and
Gradle rejected it ("Unpacked JDK archive does not contain a Java home"). `setup-java` reads the
Adoptium API directly and gets the glibc build. The `toolchain-java-version` default mirrors
the catalog `java` entry; `PlatformToolVersionMirrorTest` fails when it drifts in any workflow
under `.github/workflows/`, or when one of the three workflows loses the input. `security-scan.yml` runs only `cyclonedxBom`, which does not
compile, and keeps a single JDK.

## Dependency locking

`gradle/build-logic`, `gradle/test-fixtures` and `gradle/observability-starter` each carry a
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
`build` (in build-logic without the TestKit suite), then `dependencies`. The daily updater invokes `scripts/refresh-catalog-update.sh <base-commit>` for catalog changes.
This reads jOOQ from the selected Spring Boot BOM, regenerates the agent stack and runs both passes
with `--write-locks`. The maintainer reviews the resulting checksums in the dependency PR.
`gradle/catalog` has no file: it resolves nothing, as its empty lockfile shows. `test-fixtures` and
`observability-starter` include `gradle/build-logic` for their convention plugin, and in a composite build the
root's file verifies everything, so their files also hold the checksums of the plugin classpath.

A bump of `java`, `gradle`, `springBoot`, `springModulith`, `springAi` or `junit` also changes the stack the
`platform-agents-backend` block names in consumers. Regenerate it with `python3 scripts/agents-stack.py`; the
`versions` package test fails while `frontend/packages/versions/agents/stack.json` differs from the catalog.

## Gradle wrapper

Every Gradle module carries the same wrapper. `gradle-wrapper.properties` pins the distribution
with `distributionSha256Sum`, and the `wrapper-validation` job in `ci.yml` checks every
`gradle-wrapper.jar` against the checksums Gradle publishes; `setup-gradle` repeats that check in
each workflow that builds. A new module copies the wrapper of an existing one.

The catalog entry `gradle` is the version of those wrappers, and `PlatformGradleVersionMirrorTest`
fails when a wrapper or the `gradle-version` of `canon-cve-scan.yml` differs from it. `platform-bump`
reads the entry from the catalog of the target release and moves an older consumer wrapper up to it, with
the distribution's SHA-256. A newer wrapper stays, as the repository's own choice, and the bump says so.

A consumer may run an older Gradle than Platform does, down to `minimumConsumerGradle` in
`gradle/build-logic/gradle.properties` (9.8.1, the first Gradle that starts on JDK 27). `PlatformMinimumGradleFunctionalTest` builds a
consumer on that version, and `seniordev.settings-conventions` fails an older build with a message
that names the fix. Raising the minimum is a consumer action: a MINOR release with a CHANGELOG entry.

## Verification gate for the toolchain

Gradle's Java 27 support does not establish compatibility for every analyzer or framework;
the consumer TestKit suite in `build-logic` is the verification gate. It runs the consumer
`build` with SpotBugs, JaCoCo, PIT and CycloneDX on class-file 71, fails on "Unsupported class
file major version", and starts the packaged Spring `bootJar` from its own runtime classpath.
What each release changed is recorded in [CHANGELOG.md](../CHANGELOG.md), not here.

The next-JDK canary uses Java 28 early access without changing the Java 27 canon. JaCoCo 0.8.16
supports Java 27 and experimentally supports Java 28; SpotBugs 4.10.5 brings ASM 9.11, which reads
class-file major 72. `PlatformJava28AnalyzerFunctionalTest` compiles the Java-library fixture on the
regular toolchain and changes its class-file major to 72, then checks JaCoCo instrumentation and
analysis with the consumer's isolated tool classpath and runs SpotBugs against that class. It catches
the parser regression without requiring an EA JDK in the normal suite; it does not establish runtime
or preview-feature compatibility. The canary remains the check of the actual EA toolchain.

One exception keeps the canary measuring Platform rather than a known Gradle defect: Checkstyle runs on
the canon toolchain there. Java 28-ea+24 rejects the `ReflectionFactory` call with which Gradle 9.8.2 rebuilds the
parameters of a process-isolated worker ([gradle/gradle#39837](https://github.com/gradle/gradle/issues/39837)),
and the `Checkstyle` task neither takes JVM arguments nor passes `JAVA_TOOL_OPTIONS` to its worker. The init script
[`checkstyle-on-canon-toolchain.init.gradle.kts`](../.github/upstream-canary/checkstyle-on-canon-toolchain.init.gradle.kts)
moves only the `Checkstyle` tasks; compilation, tests, JaCoCo and SpotBugs stay on the early-access JDK.
Checkstyle reads sources, not bytecode, so its JVM does not change what the leg measures. Remove the init script
once the Gradle wrapper of the canon carries the fix.

## Frontend canon

`frontend/packages/versions/versions.json` is the frontend counterpart of the catalog and holds the frame only:
every npm package in it takes its exact version from it, and `platform-versions-check` fails `frontend-ci` on any
other version of such a package. A package the canon lacks belongs to the consumer, as an exact version in
`package.json`, and so does an `override` for it: `platform-versions-check` and `platform-bump` leave both alone, and
`--fix` rewrites only packages of the canon. Platform's own workspace follows the same rule, so its packages are
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
