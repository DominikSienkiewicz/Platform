# Where versions are declared

`gradle/catalog/libs.versions.toml` is the only place a library or plugin version is
declared. `gradle/build-logic` includes **that same file** through its own
`settings.gradle.kts`:

```kotlin
versionCatalogs { create("libs") { from(files("../catalog/libs.versions.toml")) } }
```

It reads the file rather than the published artifact because `platform-catalog` does not
yet exist at the time `build-logic` is compiled. The plugin marker artifacts on the
`build-logic` classpath therefore take their versions straight from the canonical file, and
a bump is a one-place edit.

## The one remaining duplication

`toolVersion` values inside the **sources** of the convention plugins — `checkstyle` and
`jacoco` in `java-conventions`, `spotbugs` in `quality-conventions` — and the
`googleJavaFormat("…")` formatter version in `java-conventions` cannot come from the
catalog. A precompiled script plugin does not read a version catalog at compile time, so
these values have to be literals in the code.

The canonical file holds matching entries for `checkstyle`, `jacoco` and `googleJavaFormat`,
so bumping any of them means editing both places. `PlatformToolVersionMirrorTest` in
`build-logic` fails when the `googleJavaFormat` literal, the toolchain `JavaLanguageVersion.of(…)`
in `java-conventions` (catalog `java`), the `ext["lombok.version"]` override in
`spring-modulith-conventions` (catalog `lombok`), the `archunitVersion` literal there (catalog
`archunit`) or `pitestVersion` in `quality-conventions`
(catalog `pitestTool`, the PIT engine; `pitest` is the Gradle plugin) drifts from the catalog,
and so does the `toolchain-java-version` default of the reusable workflows (catalog `java`). The formatter
version is pinned rather than left to Spotless because Spotless picks its default from the JVM
that runs Gradle, and on JDK 27 it picked a release that crashes on the new javac. `spotbugs` (`toolVersion` `4.9.8`) has no canonical entry;
`spotbugsPlugin` is the Gradle plugin version, which is a different thing.

## Overrides above the Spring Boot BOM

`spring-modulith-conventions` overrides BOM version properties through `ext[...]`:
`netty.version` and `postgresql.version` for CVEs, and `lombok.version` `1.18.48` for
compatibility — the Boot 4.1.0 BOM pins Lombok 1.18.46, which fails on javac 27, the
toolchain of `java-conventions`. Drop each override once the Boot BOM catches up.

ArchUnit is overridden differently, because no BOM manages it and so there is no property to set:
`spring-modulith-core` 2.1.0 declares ArchUnit `1.4.2` as a compile dependency, and that version cannot
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
