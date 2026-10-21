# ADR-0034: One JDK 27 runs Gradle, compiles build-logic and is the consumer toolchain

## Status

Accepted — 2026-10-21. Supersedes [ADR-0004](0004-consumer-toolchain-jdk-27.md).

## Context

[ADR-0004](0004-consumer-toolchain-jdk-27.md) moved the consumer toolchain to JDK 27 on 2026-09-25
and kept the Gradle daemon and `build-logic` on JDK 25, which was the safe JDK to start Gradle then.
That split put two JDKs on every developer machine and every CI job, and in practice it no longer held:

- The maintainer's machine has only JDK 27. Starting Gradle on it needs a Gradle that runs on JDK 27,
  and Gradle 9.6.1, Platform's declared consumer minimum, does not: its Groovy stops with
  "Unsupported class file major version 71". The canary of the 1.7.0 release failed on Azimuth for
  this reason. Gradle 9.8.1, the version of Platform's own wrappers, runs on JDK 27, and Azimuth has
  moved its wrapper to it.
- Platform's Java modules (`test-fixtures`, the starters) overrode the toolchain of
  `seniordev.java-conventions` back to 25 only so that they would load on a JDK 25 daemon. They run
  in consumers' test and application JVMs, which already need Java 27 for the consumers' own bytecode.
- Foojay now indexes the glibc build of Temurin 27 for Linux, so the reason the daemon criteria of the
  starters could not point at 27 on 2026-09-25 has gone. CI still installs JDKs with `setup-java`.

## Decision

- One JDK, the catalog's `java` (27), runs the Gradle daemon, is the toolchain that builds `build-logic`
  and Platform's Java modules, and is the toolchain `seniordev.java-conventions` gives consumers. No
  module overrides it. Platform supports Gradle on this JDK only.
- The Kotlin embedded in Gradle 9.8.1 (2.4.10) targets at most JVM 26, so `build-logic` pins its
  bytecode to 26 for Kotlin and Java, explicitly, rather than letting Kotlin fall back with a target
  mismatch warning. Platform's Java modules compile to 27.
- Every Platform workflow installs that JDK, and the `java-version` input of the reusable workflows
  defaults to it. The separate `toolchain-java-version` input stays, so a consumer or a canary can try a
  newer toolchain without moving Gradle.
- The SDKMAN files, both devcontainers and the daemon JVM criteria of the JVM starters name the same JDK.
- The oldest consumer Gradle (`minimumConsumerGradle`) is 9.8.1, the first Gradle that starts on JDK 27.
- `templates/tests/jdk-everywhere.test.sh` fails when any of these leaves the catalog's `java`, or the
  minimum falls below the first Gradle that starts on it.
- Moving consumers is a MINOR release with consumer action, per
  [ADR-0002](0002-release-and-versioning-contract.md). The release migration `1.8.0-gradle-jdk-27` moves a
  literal `java-version` of the callers of Platform's reusable workflows and `.sdkmanrc`; daemon criteria
  and any other `setup-java` are reported for a manual fix.
- What ADR-0004 decided about CI installing the toolchain with `setup-java`, the runtime image moving
  with the toolchain and the compatibility pins for JDK 27 stays in force, and so does its update on
  `-Pplatform.toolchain.override`.

## Consequences

- (+) One JDK to install, cache and patch on developer machines, in the devcontainers and on CI.
- (+) A consumer whose machine has only the current JDK can build without a second one.
- (+) The published jars target the bytecode their consumers already require; the plugins are one
  major behind until Gradle's Kotlin catches up, which no consumer notices on JDK 27.
- (−) Gradle, the Kotlin DSL and every Gradle plugin Platform applies must support the current JDK as
  soon as the toolchain moves; a toolchain move can no longer outrun Gradle. The weekly
  `upstream-canary.yml` next-JDK leg shows how far behind they are before a move.
- (−) Consumers on a Gradle older than 9.8.1, or running Gradle on JDK 25 or 26, must move before they
  can take 1.8.0.
- (−) The non-LTS cadence from ADR-0004 now applies to the daemon as well: within six months of a JDK
  GA, Gradle has to run on its successor.

## Revisit when

- JDK 28 reaches GA: move the one JDK once Gradle, the Kotlin DSL and the analyzers run on it, or
  record why Gradle has to stay behind the toolchain for a while.
- The Kotlin embedded in Gradle supports JVM target 27: raise `buildLogicBytecode` in
  `gradle/build-logic/build.gradle.kts` to 27.
- A Gradle or Kotlin release drops support for the current JDK as a daemon or a JVM target.
