# ADR-0004: Consumers compile for non-LTS JDK 27 while Gradle and build-logic run on JDK 25

## Status

Accepted — 2026-09-25 (recorded 2026-10-18)

## Context

The portfolio baseline moved to Java 27 on 2026-09-25, ten days after its GA. JDK 27 is not a
long-term-support release. Gradle and the Kotlin DSL that compiles `build-logic` run on the
JDK that starts Gradle, and on 2026-09-25 that was safely JDK 25.

The move needed several compatibility pins: Lombok 1.18.48 (the Boot BOM's 1.18.46 fails on
javac 27), google-java-format 1.36.1, PIT 1.30.0 and a runtime-managed ArchUnit 1.5.0
(Spring Modulith pulled 1.4.2, which cannot read class-file 71). Docker Hub had no Temurin 27
image, so the runtime image became `sapmachine:27-jre`. Foojay indexed only the Alpine build of
Temurin 27 for Linux, so CI installs the toolchain with `actions/setup-java` instead.

## Decision

- `seniordev.java-conventions` compiles consumer code with the JDK 27 toolchain (catalog
  `java`).
- Gradle and `build-logic` keep running on JDK 25. `build-logic` targets Java 25 bytecode so
  that the plugins load on the JDK that runs Gradle.
- CI installs the toolchain JDK with `actions/setup-java` (input `toolchain-java-version`,
  default from catalog `java`) and registers it through `org.gradle.java.installations.paths`.
- The runtime image moves with the toolchain: `templates/Dockerfile.backend` runs a JRE of the
  same major, and `platformRuntimeImageCheck` fails a consumer's `check` when its Dockerfile runs
  an older Java.
- The compatibility pins are mirrored literals guarded by the mirror tests, and the TestKit
  consumer build runs every analyzer on the toolchain's class files.

## Consequences

- (+) Consumers use current language and JVM features, and a single toolchain applies across
  the portfolio.
- (+) Each pin needed for JDK 27 is written down and guarded, so its removal condition can be
  checked.
- (−) A non-LTS JDK must be followed to its successor within its six-month support window.
  Each toolchain move is a MINOR release with consumer action (runtime image, CI JDK), per
  [ADR-0002](0002-release-and-versioning-contract.md).
- (−) Two JDKs are needed on CI and on developer machines.

## Revisit when

- JDK 28 reaches GA: move the toolchain, or record why the portfolio stays.
- A Temurin 27 image passes the container scan gate: move the runtime image back, as
  [docs/versions.md](../versions.md) describes.
- The Boot BOM, Spring Modulith or the tools ship versions that make a pin unnecessary.
