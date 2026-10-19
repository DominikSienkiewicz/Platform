# Add a JVM library

**Preconditions:** the library is needed by a consumer and is not managed by a Platform BOM (a Spring Boot starter
needs no catalog entry: declare it without a version).

In Platform:

1. Add the version and the library to `gradle/catalog/libs.versions.toml`, for example
   `jsoup = "1.23.2"` and `jsoup = { group = "org.jsoup", name = "jsoup", version.ref = "jsoup" }`.
2. If a Platform module resolves it, run `scripts/write-verification-metadata.sh`.
3. Note it under `### Added` in `CHANGELOG.md`, then release ([cut a release](cut-release.md)).

In the consumer:

4. `scripts/platform-bump.sh X.Y.Z` to the release that carries the entry.
5. Declare it as `implementation(libs.jsoup)`, with no version.
6. Run `./gradlew platformDependencyCheck`.

**Done when:** `./gradlew platformDependencyCheck` prints "platformDependencyCheck: OK".
