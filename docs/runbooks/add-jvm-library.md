# Add a JVM library

**Preconditions:** the library is needed by a consumer and is not managed by a Platform BOM (a Spring Boot starter
needs no catalog entry: declare it without a version).

**Decide first: frame or application.** Platform governs the frame; a library outside it belongs to the application
([ADR-0037](../adr/0037-platform-governs-the-frame.md)).

- Used by one repository: do not touch Platform. Register `appLibs` from `backend/gradle/app.versions.toml` as
  [Libraries your application owns](../consuming.md#libraries-your-application-owns) shows, declare it as
  `implementation(appLibs.own.library)`, and run `./gradlew platformDependencyCheck`. A library a BOM manages takes no
  version.
- Used by two or more repositories: it belongs to the frame, so follow the steps below.

In Platform:

1. Add the version and the library to `gradle/catalog/libs.versions.toml`, for example
   `shared-lib = "1.0.0"` and `shared-lib = { group = "com.example", name = "shared-lib", version.ref = "shared-lib" }`.
2. If a Platform module resolves it, run `scripts/write-verification-metadata.sh`.
3. Note it under `### Added` in `CHANGELOG.md`, then release ([cut a release](cut-release.md)).

In the consumer:

4. `scripts/platform-bump.sh X.Y.Z` to the release that carries the entry.
5. Declare it as `implementation(libs.shared.lib)`, with no version.
6. Run `./gradlew platformDependencyCheck`.

**Done when:** `./gradlew platformDependencyCheck` prints "platformDependencyCheck: OK".
