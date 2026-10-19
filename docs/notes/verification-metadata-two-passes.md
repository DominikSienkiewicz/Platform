# Dependency verification that passed locally and failed in CI

**Symptom.** After the bump from 1.5.4 to 1.5.22, BookOfStyling and SkillSprintPlus built locally and
failed in CI with "Dependency verification failed" for `junit-bom-5.14.4.pom`. After the bump to 1.5.26,
Azimuth and SkillSprintPlus failed the same way for `junit-bom-6.1.3.pom`.

**Root cause.** Two different holes in `gradle/verification-metadata.xml`:

- With a warm Gradle cache, Gradle serves module metadata from its own store and never touches the `.pom`
  or `.module` file, so `--write-verification-metadata` records no checksum for it. CI starts cold,
  downloads the file and finds no entry.
- `build` only sees the configurations in its task graph. `junit-bom-6.1.3.pom` is fetched in a detached
  configuration that the Spring dependency-management plugin creates while resolving `integrationTest`,
  and the same applies to tool configurations such as Spotless, JaCoCo and CycloneDX.

**Fix.** `platform-bump` regenerates the file in two passes, both with `--refresh-dependencies`:
`build`, which downloads the jars, then `dependencies` without `--configuration`, which resolves every
resolvable configuration and closes the metadata. `--write-locks` goes with both, and `--dry-run` never,
because Gradle would then write a separate file and report success. The reasons sit next to the commands in
[`platform-bump.sh`](../../frontend/packages/versions/bin/platform-bump.sh).

**Guards.** Platform's own modules use the same two passes through
[`scripts/write-verification-metadata.sh`](../../scripts/write-verification-metadata.sh) and verify
strictly; [versions.md](../versions.md#dependency-verification) documents the rule.
