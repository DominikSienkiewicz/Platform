# Changelog

Changes to the published Platform artifacts, newest first. All artifacts share one version. A
release that needs action in consumer repositories bumps the MINOR version in the 1.x line and
lists that action under **Consumer action required**.

## Unreleased

### Consumer action required

- `platformDependencyCheck` now also governs dependency constraints, every declarable bucket
  (`compileOnlyApi`, `developmentOnly`, `testAndDevelopmentOnly`, `testFixtures*` and custom
  source sets) and `pl.seniordeveloper` artifacts. Remove explicit versions from those
  declarations, or declare the dependency through `libs.<alias>`.

### Changed

- `platformDependencyCheck` messages are in English and name the fix: the `libs.…` alias to
  use, a BOM-managed version to remove, or a library to add to the Platform catalog first.
- `platform-catalog` gains a `spotbugs` version entry, the canon of the SpotBugs
  `toolVersion` in `seniordev.quality-conventions`.
- The catalog's `platform` placeholder is now `0.0.0-injected-at-publish`, a version that cannot
  resolve, instead of the real release `1.4.3`. Published catalogs carry the injected
  release version as before.
- The JVM starters in `templates/jvm/` are pinned to the latest release.
