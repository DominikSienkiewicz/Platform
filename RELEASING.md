# Releasing Platform

The model is **publish-only with deliberate versioning**. GitHub Packages (Maven and npm) is the
only source of truth for released artifacts. A single `platformVersion` in
`gradle/build-logic/gradle.properties` is the version of every artifact, on GitHub Packages and in
consumers' pins alike. [`release.yml`](.github/workflows/release.yml) publishes that version and
runs only when someone asks for it: a pushed `vX.Y.Z` tag or a manual `workflow_dispatch`. Nothing
bumps versions automatically, and nothing prunes old versions automatically. What a version number
means and what every release must carry is the
[release and versioning contract](docs/adr/0002-release-and-versioning-contract.md).

There are two distribution channels, and they move differently:

- **Artifacts are pinned.** Consumers pin the exact platform version and move it with
  `scripts/platform-bump.sh` (or Renovate). Nothing changes for them until they bump.
- **Reusable workflows float.** Consumers call them as
  `uses: DominikSienkiewicz/Platform/.github/workflows/<name>.yml@v1`. `v1` is a moving major tag
  that `release.yml` moves forward after every successful release, so a workflow change reaches
  every consumer on its next CI run.

The current version is not repeated here, because a copy goes stale. Read it from the source:

```bash
grep '^platformVersion=' gradle/build-logic/gradle.properties
```

```bash
git tag --list 'v*.*.*' --sort=-v:refname | head -1
```

## What a release publishes

Every artifact below is published at the same `platformVersion`.

| Source | Artifact | Registry |
|---|---|---|
| `gradle/build-logic/` | `pl.seniordeveloper.gradle:build-logic` plus plugin markers for `seniordev.java-conventions`, `seniordev.quality-conventions`, `seniordev.spring-modulith-conventions` and `seniordev.settings-conventions` | GitHub Packages (Maven) |
| `gradle/catalog/` | `pl.seniordeveloper:platform-catalog` | GitHub Packages (Maven) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` | GitHub Packages (Maven) |
| `gradle/security-starter/` | `pl.seniordeveloper:platform-security-starter` | GitHub Packages (Maven) |
| `frontend/packages/tsconfig/` | `@dominiksienkiewicz/tsconfig` | GitHub Packages (npm) |
| `frontend/packages/eslint-config/` | `@dominiksienkiewicz/eslint-config` | GitHub Packages (npm) |
| `frontend/packages/tailwind-preset/` | `@dominiksienkiewicz/tailwind-preset` | GitHub Packages (npm) |
| `frontend/packages/vitest-config/` | `@dominiksienkiewicz/vitest-config` | GitHub Packages (npm) |
| `frontend/packages/versions/` | `@dominiksienkiewicz/versions` | GitHub Packages (npm) |
| `frontend/packages/api-client/` | `@dominiksienkiewicz/api-client` | GitHub Packages (npm) |
| `frontend/packages/query/` | `@dominiksienkiewicz/query` | GitHub Packages (npm) |
| `frontend/packages/ui-registry/` | `@dominiksienkiewicz/ui` | GitHub Packages (npm) |

The npm job publishes every workspace package under `frontend/packages/` that is not marked
`"private": true`, so a new package is released as soon as it exists. Update this table and the
README in the same change.

## One-time setup

```bash
# A) Local GitHub Packages credentials, read by Gradle automatically, in ~/.gradle/gradle.properties:
gpr.user=<your GitHub user>
gpr.key=<classic PAT with read:packages>       # add write:packages only to publish from your machine

# B) npm: the project .npmrc reads ${GITHUB_TOKEN}; keep it in your shell profile or an ignored file.
export GITHUB_TOKEN=<classic PAT with read:packages>

# C) Consumer repositories need a GPR_TOKEN secret (classic PAT with read:packages) for CI.
```

## Cutting a release

1. Bump the pinned actions by hand. Every action in `.github/workflows/` is pinned by commit SHA
   with a `# vX.Y.Z` comment, and Renovate does not run in Platform yet, so nothing moves them.
   Check each one against its latest release and update SHA and comment together.
2. Prepare the notes. In [CHANGELOG.md](CHANGELOG.md), rename `## [Unreleased]` to
   `## [X.Y.Z] - YYYY-MM-DD` and start a new empty `## [Unreleased]` above it. The section must
   have a `### Consumer action required` subsection; write `None.` when nothing is required. Pick
   the number by the [contract](docs/adr/0002-release-and-versioning-contract.md): consumer
   action means a MINOR, anything else a PATCH.
3. Commit and push those changes through the normal branch and merge flow, so `main` equals
   `origin/main` with a clean tree.
4. Release:

```bash
./release.sh "fix: short description"
```

```bash
./release.sh "feat: short description" 1.6.0
```

The first form releases a patch (current version + 0.0.1), the second an explicit version. Append
`-y` after the version, or set `ASSUME_YES=1`, to skip the confirmation prompt. The message is
required: an English Conventional Commit, which becomes the body of the release commit
`chore(release): platform X.Y.Z`.

Before it changes anything, `release.sh` refuses to run when:

- the working tree is not clean (untracked files included), the current branch is not `main`, or
  `HEAD` differs from `origin/main`;
- the message is not a Conventional Commit or contains Polish characters;
- the version's tag already exists;
- CHANGELOG.md has no section for the version, or the section has no
  `### Consumer action required` subsection;
- the release would be a patch although its section lists consumer action; the error names the
  MINOR version to use;
- the message is `feat`, uses `!:` or carries `BREAKING CHANGE`, and no version was given.

It then bumps `platformVersion` in every `gradle/*/gradle.properties` and
`templates/jvm/*/gradle.properties`, and `version` in every `frontend/packages/*/package.json`,
commits only those files, pushes `main`, and creates and pushes the annotated `vX.Y.Z` tag, whose
message is the CHANGELOG section. It does not touch `v1`. The tree therefore always carries one
version; `templates/tests/platform-version-sync.test.sh` fails when a file drifts or a build script
falls back to a hard-coded version, and `templates/tests/release-contract.test.sh` pins every
refusal above.

The `vX.Y.Z` tag starts `release.yml`. Moving `v1` does not: the trigger only matches `v*.*.*`,
because two publishes of the same version running in parallel once caused a partial release.

To publish an existing tag again, run **Actions → Release (version tag) → Run workflow** on that
tag. A dispatch from a branch fails, because a release runs only from the tag that equals
`platformVersion`. Read the idempotency rules below first.

## What `release.yml` does

1. **`version`** reads `platformVersion` from `gradle/build-logic/gradle.properties` and fails
   unless the run started from the tag `v<platformVersion>`, so every published version has its
   tag and every tag has its version.
2. **`verify`** runs the full CI (`ci.yml`) on the tagged commit, and **`registry-build`** builds
   the shadcn registry without `packages: write`. Both must be green before anything is published.
3. **`gradle`** and **`npm`** then run in parallel. One can fail while the other succeeds, so a
   release can be complete in one registry and missing in the other. Check both jobs before you
   announce a release.
4. **`move-v1`** moves `v1` to the released commit after both publish jobs succeed, and only
   forward: re-running an older tag never moves it back. Never move `v1` by hand.
5. **`github-release`**, also after both publish jobs, creates the GitHub Release `vX.Y.Z` titled
   "Platform X.Y.Z". Its notes are the version's CHANGELOG.md section, extracted by
   `scripts/changelog-section.sh`, plus a link to the diff from the previous version. A re-run
   leaves an existing Release alone.
6. **`verify-published`**, after both publish jobs, fails unless every artifact carries the
   version: the main build-logic artifact, the marker of every convention plugin, the catalog,
   test-fixtures, security-starter and every npm package not marked `private`. The publish jobs
   skip versions that already exist, so this is the one place that proves the release is complete.

A red job stops every job after it. A tag on a commit with red CI publishes nothing, leaves `v1`
where it was and creates no GitHub Release.

### Idempotency, per registry

Versions are immutable on GitHub Packages: a published version cannot be overwritten. A broken
release is fixed by releasing a new version, or by deleting the broken version and re-running.

**Maven (`gradle` job).** Before each module, the job asks the GitHub Packages API whether the
version already exists.

- If it exists, the whole module is skipped. `build-logic` is checked by its
  `seniordev.settings-conventions` plugin marker, not by its main artifact: the main artifact is
  uploaded first and can exist while the markers are missing, and the settings marker is the
  artifact a consumer resolves first.
- If it does not exist, the module is published and **any failure is fatal, including HTTP 409**.
  A 409 on the `.pom` makes Gradle stop the module before it uploads the Gradle Module Metadata
  (`.module`), which leaves an artifact without its catalog or plugin variant. Consumers then fail
  with "No matching variant". Swallowing the 409 is what broke `platform-catalog:1.3.4`.

Re-running after a successful Maven publish is safe: every module is skipped. **Re-running after a
failed Maven publish is not.** If any file of the failed module was uploaded, the pre-check sees the
version, skips the module and leaves the incomplete artifact in place. Before re-running, delete
that version of the affected package on GitHub Packages, or release a higher version instead.

**npm (`npm` job).** Each package is handled on its own:

- packages marked `"private": true` are skipped;
- if `npm view <name>@<version>` finds the version, the package is skipped;
- otherwise the package is published; a version-conflict response (`E409`, `409 Conflict`,
  `cannot publish over`) is treated as already published;
- any other failure marks the job failed, but the remaining packages are still attempted.

An npm package is published in a single request, so re-running the job after a partial failure is
safe: it publishes only the packages that are still missing.

## Consumers: adopting a new version

In a consumer repository:

```bash
./scripts/platform-bump.sh
```

Without an argument the script bumps to the newest release of the consumer's current MAJOR
version; when a newer MAJOR exists it says so and leaves crossing it to an explicit version. Pass
a version (`./scripts/platform-bump.sh 1.6.0`) to pin a specific one. It is a stub that calls the
`platform-bump` bin of `@dominiksienkiewicz/versions`, reads its token from `GPR_TOKEN`,
`GITHUB_TOKEN` or `gpr.key`, and:

- prints the GitHub Release notes of every version after the current pin up to the target, and
  repeats their **Consumer action required** entries at the end, followed by a link to the target
  release. The stub runs the installed copy of the bin, so the notes appear from the bump after
  the one that installs a version with this feature;
- rewrites the settings plugin and catalog pins in `backend/settings.gradle.kts` and
  `backend/settings-gradle.lockfile`, and a `platformVersion=` pin in `backend/gradle.properties` or
  a root `gradle.properties`; convention plugins in `build.gradle.kts` carry no version. It fails
  when the layout has no pin, instead of reporting success;
- applies the frontend version canon to `frontend/package.json`, including `overrides`, and
  regenerates `package-lock.json`;
- moves every `uses: DominikSienkiewicz/Platform/.github/workflows/<name>.yml@<ref>` in
  `.github/workflows/` to the target tag, `@v1` included, and so does a `platform-ref:` input of a
  `deploy.yml` caller; a reference by commit SHA stays;
- regenerates `gradle.lockfile` and, when the repository verifies dependencies,
  `gradle/verification-metadata.xml`.

The script does not commit; the diff is left for review. The reusable
[`platform-bump.yml`](docs/reusable-workflows.md#platform-bumpyml) runs the same bin on a schedule and
opens the pull request.

### Why dependency verification needs two Gradle passes

With `gradle/verification-metadata.xml` present, the bump runs Gradle twice, both times with
`--refresh-dependencies`, so it takes noticeably longer:

| Pass | Purpose |
| --- | --- |
| `build --write-locks --write-verification-metadata sha256` | downloads artifacts, so it is the only pass that records **jar** checksums; it sees only the configurations in the `build` graph |
| `dependencies --write-locks --write-verification-metadata sha256` | resolves **every** resolvable configuration, so it completes the **metadata** (`.pom`/`.module`) outside the `build` graph; as a report task it downloads no jars |

Both `--refresh-dependencies` flags are deliberate. With a warm cache Gradle does not touch the
`.module` files, their checksums never reach the metadata file, and CI on a cold cache fails with
`Dependency verification failed`. The second pass is just as deliberate: `junit-bom-<version>.pom`
is fetched only by the detached configuration that `io.spring.dependency-management` creates while
resolving `:integrationTest`, outside the `build` graph, so the first pass alone left a gap (Azimuth
and SkillSprintPlus, bump to 1.5.26). The same class of failure hit tool configurations earlier
(Spotless, JaCoCo, CycloneDX), which is why the pass is not narrowed with `--configuration`.

Never add `--dry-run` to these calls. Gradle then writes `verification-metadata.dryrun.xml`, leaves
the real file untouched and still reports `BUILD SUCCESSFUL`.

### Testing an unreleased change

Do not release just to try a change in a consumer. Publish locally and point the consumer at that
repository with `-PplatformRepository`, as described in
[docs/local-development.md](docs/local-development.md).

## Package retention

Old versions are never pruned automatically, neither in `release.yml` nor on a schedule. The
support rule is: **no version that a consumer still pins may be deleted**, and a consumer stays on
a deleted version only by accident. Clean up deliberately with
**Actions → Cleanup old package versions → Run workflow**:

- `protect` (required): every version a consumer still pins, comma-separated, for example
  `1.5.26,1.5.31`. Read the pins from each consumer's `backend/settings.gradle.kts` before the run.
  Protected versions are never deleted, whatever their age.
- `keep` (default `10`): how many of the newest versions of each package to keep.
- `dry_run` (default `true`): print the plan only. Review it, then run again with `dry_run`
  unticked to delete.

The workflow runs [`scripts/cleanup-packages.sh`](scripts/cleanup-packages.sh), which touches only
Platform packages and refuses to run without `protect`. It needs a `PACKAGES_ADMIN_TOKEN` secret
(classic PAT with `read:packages` and `delete:packages`). GitHub can restore a deleted package
version for 30 days; after that it is gone.
