# ADR-0013: The catalog carries aliases and versions, platform-bom carries constraints

## Status

Accepted — 2026-10-19

## Context

Platform published its versions only as a version catalog, and `docs/versions.md` explained why there was
no `java-platform` BOM. A TOML catalog holds aliases and versions, but it cannot express a constraint: a
CVE floor on a transitive library, the reason for it, or the import of the Spring BOMs. So the overrides
lived as `ext["…version"]` properties inside `seniordev.spring-modulith-conventions`, which reach only
builds that apply that plugin, and consumers wrote their own in three different mechanisms (Azimuth an
`eachDependency` block, BookOfStyling `extra["jackson-bom.version"]`, SkillSprintPlus `eachDependency`
on jackson-databind). Platform's own libraries each re-imported the Boot BOM.

## Decision

`gradle/bom` publishes `pl.seniordeveloper:platform-bom`, a `java-platform` with `allowDependencies()`:

- it imports the Spring Boot, Spring Modulith, Spring AI and JUnit BOMs and the fixed Jackson 3 and
  Jackson 2 BOMs, Jackson first, so the first-import-wins rule of `io.spring.dependency-management` and
  Gradle's highest-version rule select the same fix;
- its `constraints` hold the CVE floors (Tomcat) and the compatibility overrides (Lombok, ArchUnit), each
  with a `because(...)` reason, and the Platform artifacts at the release version.

Every version in it comes from `gradle/catalog/libs.versions.toml` (hard rule 1); the catalog stays the
single source of versions and the only place consumers declare aliases. `platform-test-fixtures` and
`platform-security-starter` import `platform-bom` instead of the separate BOMs.

`seniordev.spring-modulith-conventions` keeps its direct BOM imports and `ext` overrides for now. Moving
it to `mavenBom("pl.seniordeveloper:platform-bom:…")` changes how `io.spring.dependency-management`
treats nested imports and a consumer's own `extra["jackson-bom.version"]`, which only a TestKit run with
`dependencyInsight` can confirm.

## Consequences

- A consumer without Spring, or a module that does not apply the Spring conventions, gets the same CVE
  floors with `implementation(platform(libs.platform.bom))`.
- The overrides exist twice until the conventions import the BOM: in `PlatformVersions` (for the
  conventions) and in `platform-bom`. Both read the catalog, so they cannot drift, but both must be
  removed when Boot manages fixed versions.
- One more published artifact, *incubating* until a consumer declares it (Decision 7).

## Revisit when

A TestKit run shows `dependencyInsight` selecting the BOM's Lombok, Jackson and Tomcat through
`mavenBom("pl.seniordeveloper:platform-bom")`, including a consumer that sets `jackson-bom.version`:
then the conventions import the BOM, their `ext` overrides go, and consumers delete their own blocks.
