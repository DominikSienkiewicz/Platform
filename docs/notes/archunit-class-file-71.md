# Spring Modulith found no classes on Java 27

**Symptom.** After the move to the Java 27 toolchain (1.5.29), consumer applications failed to start with
"No classes found in packages" from Spring Modulith. Every test was green.

**Root cause.** `spring-modulith-core` 2.1.1 declares ArchUnit 1.4.2 as a compile dependency, and ArchUnit
1.4.2 cannot read class-file major version 71, which javac 27 writes. Spring Modulith builds
`ApplicationModules` with ArchUnit at application start, so on the runtime classpath it imported nothing.
The tests never saw it: `archunit-junit5` from the catalog put ArchUnit 1.5.0 on the test classpaths only.

**Fix.** 1.5.30. [`seniordev.spring-modulith-conventions`](../../gradle/build-logic/src/main/kotlin/seniordev.spring-modulith-conventions.gradle.kts)
manages `com.tngtech.archunit:archunit` in `dependencyManagement.dependencies` at the catalog's `archunit`
version, which applies to every configuration, transitive dependencies and the runtime classpath included.
No BOM manages ArchUnit, so there is no property to override instead.

**Guards.** [`PlatformToolVersionMirrorTest`](../../gradle/build-logic/src/test/kotlin/pl/seniordeveloper/gradle/PlatformToolVersionMirrorTest.kt)
fails when the managed dependency disappears, and the version comes from the catalog through
`PlatformVersions`. The removal condition is written down: drop it once `spring-modulith-core` depends on
ArchUnit 1.5.0 or later ([versions.md](../versions.md#overrides-above-the-spring-boot-bom),
[ADR-0008](../adr/0008-overrides-are-a-last-resort.md)).
