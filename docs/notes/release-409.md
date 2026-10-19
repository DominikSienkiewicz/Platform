# A swallowed 409 published a catalog without its variant

**Symptom.** After the 1.3.4 release, consumers bumping to it failed with "No matching variant" for
`pl.seniordeveloper:platform-catalog:1.3.4`. Gradle found the POM but no version-catalog variant to use.

**Root cause.** The release workflow treated a `409 Conflict` from GitHub Packages as "already
published" and moved on. A conflict on the `.pom` aborts Gradle's upload of that module before the
`.module` file (Gradle Module Metadata) goes up, and the `.module` is what carries the catalog and
plugin-marker variants. The registry kept a POM without metadata, and a version on GitHub Packages
cannot be published again. The same pattern later left the build-logic plugin markers missing on 1.5.1 to
1.5.3, because the workflow keyed "done" on the main artifact while the markers had failed.

**Fix.** 1.3.5 and 1.5.4 replaced the broken releases. [`release.yml`](../../.github/workflows/release.yml)
now asks the GitHub API whether a version exists before publishing a module (keyed on the settings plugin
marker for build-logic), treats every publish error as fatal, and never swallows a 409.

**Guards.** `verify-published` fails a release unless every artifact, every plugin marker included,
carries the version; `verify-consumable` then resolves the release from GitHub Packages as a consumer
does. [`releases/yanked.txt`](../../releases/yanked.txt) keeps `platform-bump` from offering 1.3.4 and
1.5.1–1.5.3, and [the rollback runbook](../runbooks/rollback.md) says how to retire a bad release.
