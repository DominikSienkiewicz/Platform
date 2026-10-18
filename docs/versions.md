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

## Runtime image for the JDK 27 toolchain

Bytecode 27 needs a runtime of at least 27, and the consumers' images derive from
`templates/Dockerfile.backend`, so the toolchain and the runtime image move together.

On 2026-09-25 the toolchain 27 entry condition was met with `sapmachine:27-jre`, not
`eclipse-temurin:27-jre`: ten days after the JDK 27 GA, Docker Hub still had no Temurin 27
image. SapMachine is an official Docker Hub image (SAP's OpenJDK build) based on Ubuntu 24.04, and it runs the template unchanged: `groupadd`/`useradd`, `bash` and `sh` are
present, `/usr/bin/pebble` is not. At the switch neither image carried a Critical or High
vulnerability (Docker Scout, `linux/amd64`); SapMachine carried 34 Medium and 2 Low, Temurin 26
none, because its base is the older Ubuntu LTS.

Move back to `eclipse-temurin:27-jre` when that tag exists and a Grype scan of it passes the
`container-scan.yml` gate (`high`, `only-fixed`). Change only the `FROM` line; the rest of the
template is image-neutral.

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

## Foundation refresh (2026-10-13)

The backend baseline is Gradle 9.8.1, Boot 4.1.1, Modulith 2.1.1 and Spring AI 2.0.1.
The frontend canon and the ESLint compatibility consumer use Next / eslint-config-next
16.4.0. Wrapper distributions include the official SHA-256 checksum. Security-starter
and test-fixtures now import the same source catalog for their BOMs.

Upstream references: [Gradle 9.8.1](https://docs.gradle.org/9.8.1/release-notes.html),
[Next 16.4.0](https://github.com/vercel/next.js/releases/tag/v16.4.0),
[Boot 4.1.1 BOM](https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-dependencies/4.1.1/spring-boot-dependencies-4.1.1.pom),
[Modulith 2.1.1 POM](https://repo.maven.apache.org/maven2/org/springframework/modulith/spring-modulith-core/2.1.1/spring-modulith-core-2.1.1.pom).

Java 27 remains the consumer toolchain. Gradle's Java 27 support does not establish
compatibility for every analyzer or framework; the consumer TestKit suite is the
verification gate. It runs the consumer `build` with SpotBugs, JaCoCo, PIT and CycloneDX on
class-file 71, fails on "Unsupported class file major version", and starts the packaged
Spring `bootJar` from its own runtime classpath.

pnpm 12 and Vitest 5 remain separate major migrations; the current release retains
pnpm 11.18.0 and Vitest 4 peers. A full OpenAPI validation/generation/freshness/breaking-change
pipeline remains a separate extension: its baseline source and consumer migration
contract must be defined before adoption.
