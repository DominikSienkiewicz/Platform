# The toolchain resolver picked a musl JDK on a glibc runner

**Symptom.** On 2026-09-25, the first CI runs with the Java 27 toolchain failed on GitHub's Ubuntu runners
with "Unpacked JDK archive does not contain a Java home".

**Root cause.** The Foojay toolchain resolver provisions a missing JDK for Gradle. That day it indexed
Temurin 27 for Linux only as the Alpine (musl) build. The resolver prefers Temurin, downloaded that archive
on a glibc machine, and Gradle rejected what it unpacked.

**Fix.** The reusable [`backend-ci.yml`](../../.github/workflows/backend-ci.yml), `deploy.yml` and `sonar.yml`
install the toolchain JDK with `actions/setup-java`, which reads the Adoptium API directly and gets the glibc
build, and register it through `org.gradle.java.installations.paths`. Gradle runs on the same JDK 27 since 1.8.0
([ADR-0034](../adr/0034-one-jdk-27-for-gradle-build-logic-and-toolchain.md)); it ran on JDK 25 before. Foojay stays as the local fallback through the settings plugin.

**Guards.** The `toolchain-java-version` default of those workflows equals the catalog's `java` entry;
[`PlatformToolVersionMirrorTest`](../../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformToolVersionMirrorTest.kt)
fails when it drifts or a workflow loses the input. [versions.md](../versions.md#jdk-27-toolchain-on-ci)
records the reason.
