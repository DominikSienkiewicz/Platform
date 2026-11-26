# Releasing Platform

The model is **publish-only with deliberate versioning**. GitHub Packages (Maven and npm) is the
only source of truth for released artifacts. A single `platformVersion` in
`gradle/build-logic/gradle.properties` is the version of every artifact, on GitHub Packages and in
consumers' pins alike. [`release.yml`](.github/workflows/release.yml) publishes that version and
runs on a pushed `vX.Y.Z` tag or a dispatch at that tag. The maintainer can cut a release locally.
For dependency updates, merging the prepared pull request approves its version and starts the same
release workflow. The numbering and release notes follow the
[release and versioning contract](docs/adr/0002-release-and-versioning-contract.md).

Consumers pin everything to one release and move it with `scripts/platform-bump.sh`, or on a
schedule with the reusable `platform-bump.yml`, which opens the pull request. The move from 1.x
to 2.0.0 requires the [organization launcher](docs/consuming.md#move-a-1x-consumer-to-200).

- **Artifacts** are pinned to the exact platform version.
- **Reusable workflows** are called by the exact tag,
  `uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/<name>.yml@vX.Y.Z`, which the bump moves with the
  pins. There is no floating `v1` tag any more (retired, [ADR-0014](docs/adr/0014-exact-pins-moved-by-platform-bump.md)):
  an external caller of `@v1` must pin an exact `vX.Y.Z`.

Renovate's shared preset (`default.json`) updates what the application owns: its Gradle and npm dependencies,
pinned exactly, GitHub Actions and Docker images. It bumps no Platform pin and no frame entry (the catalog, the
frontend canon, the Gradle wrapper, Platform's artifacts and reusable workflows): `scripts/renovate-preset.py`
generates those `Frame:` rules with `enabled: false`, and `platform-bump` moves the frame.

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
| `gradle/build-logic/` | `pl.seniordeveloper.gradle:build-logic` plus plugin markers for `seniordev.java-conventions`, `seniordev.quality-conventions`, `seniordev.spring-modulith-conventions`, `seniordev.sonar-conventions`, `seniordev.nullness-conventions` and `seniordev.settings-conventions` | GitHub Packages (Maven) |
| `gradle/catalog/` | `pl.seniordeveloper:platform-catalog` | GitHub Packages (Maven) |
| `gradle/bom/` | `pl.seniordeveloper:platform-bom` | GitHub Packages (Maven) |
| `gradle/test-fixtures/` | `pl.seniordeveloper:platform-test-fixtures` | GitHub Packages (Maven) |
| `gradle/observability-starter/` | `pl.seniordeveloper:platform-observability-starter` | GitHub Packages (Maven) |
| `frontend/packages/tsconfig/` | `@seniordeveloper-pl-dominik-sienkiewicz/tsconfig` | GitHub Packages (npm) |
| `frontend/packages/eslint-config/` | `@seniordeveloper-pl-dominik-sienkiewicz/eslint-config` | GitHub Packages (npm) |
| `frontend/packages/tailwind-preset/` | `@seniordeveloper-pl-dominik-sienkiewicz/tailwind-preset` | GitHub Packages (npm) |
| `frontend/packages/vitest-config/` | `@seniordeveloper-pl-dominik-sienkiewicz/vitest-config` | GitHub Packages (npm) |
| `frontend/packages/prettier-config/` | `@seniordeveloper-pl-dominik-sienkiewicz/prettier-config` | GitHub Packages (npm) |
| `frontend/packages/versions/` | `@seniordeveloper-pl-dominik-sienkiewicz/versions` | GitHub Packages (npm) |
| `frontend/packages/openapi/` | `@seniordeveloper-pl-dominik-sienkiewicz/openapi` | GitHub Packages (npm) |

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

## Repository settings

The GitHub settings this repository depends on are code: `.github/rulesets/*.json` and
`scripts/repo-settings.sh`. Run `scripts/repo-settings.sh --check` (GET requests only) to see drift
and `scripts/repo-settings.sh --apply` to fix it, with `gh` logged in as an admin of the repository.
It keeps:

- the rulesets: `main` cannot be deleted or force-pushed; release tags `v*.*.*` cannot be deleted or
  moved, so a published version keeps its source;
- secret scanning with push protection, Dependabot alerts without its security-update pull requests
  (`platform-bump` moves versions), private vulnerability reporting, the requirement to pin every
  action by commit SHA, and automatic deletion of merged head branches.

Platform does not analyse its own modules in SonarQube Cloud
([ADR-0012](docs/adr/0012-platform-scans-itself-in-sonarqube-cloud.md), superseded); the Sonar configuration of
`seniordev.quality-conventions` and `seniordev.sonar-conventions` serves consumers only, so the repository needs
no `SONAR_TOKEN` secret.

The `consumer-impact.yml` workflow labels a pull request `consumer-action` when
`scripts/canon-diff.py` finds a change consumers must act on: a removed catalog alias or canon
package, or a reusable workflow that loses an input or secret, gains a required input or a
permission, or changes a default. Create the label once (`gh label create consumer-action`); until
it exists the job only warns. Such a change calls for at least a MINOR release with a **Consumer action required** entry.

It never deletes a branch: it lists remote branches already merged into `main` with the command that
deletes them. `--consumers` also checks every repository in `scripts/consumers.txt` for what
`platform-bump.yml` needs: GitHub Actions may create pull requests there, and a `PLATFORM_BUMP_TOKEN`
secret exists (the secret is only reported; its value is yours to set).

## First organization release

The registry move is a MAJOR distribution change under [ADR-0002](docs/adr/0002-release-and-versioning-contract.md).
Keep `1.13.1` in the release-managed version files during preparation. Once the changes are integrated and
the release preconditions hold, the owner selects the explicit version:

```bash
./release.sh "feat: publish Platform packages under the organization" 2.0.0
```

The release gate verifies the first 2.x release against its published 1.x predecessor.
The frontend image smoke resolves 1.13.1 from public release archives and verifies the checksum
manifest with the historical signing workflow and release commit. The backend smoke directs the
historical plugin to the organization Maven endpoint. Both checks run before 2.0.0 packages exist.

Before cutting the tag, confirm that the workflow can publish GitHub Packages under
`SeniorDeveloper-pl-Dominik-Sienkiewicz` and can create artifact attestations. A consumer's
`GPR_TOKEN` or repository Actions package access must permit reads of the organization packages.
An account's login is still the Gradle username. The Maven endpoint uses the lowercase organization in
`https://maven.pkg.github.com/seniordeveloper-pl-dominik-sienkiewicz/Platform`.

After publication, check that release verification succeeded for the organization Maven modules and
all seven npm packages, and that `v2.0.0` contains `SHA256SUMS`, the attestation bundle and
`seniordeveloper-pl-dominik-sienkiewicz-versions-2.0.0.tgz`.
Existing 1.x consumers should then [bootstrap the 2.0.0 launcher](docs/consuming.md#move-a-1x-consumer-to-200).

## Daily dependency releases

At **04:23 UTC** the [daily workflow](.github/workflows/daily-dependencies.yml) runs Renovate against
Platform. It can also be started from **Actions → Daily dependency updates → Run workflow** on `main`.
Spring BOMs, explicit catalog pins such as Tomcat, the frontend canon and GitHub Actions are checked
for stable releases. The consumer preset gives ordinary releases three days to mature. Recognized
security updates can be proposed on the next run. The daily [CVE scan](docs/versions.md#cve-response)
also covers transitive dependencies. A fix that requires a new BOM override follows the CVE response procedure.

### One-time GitHub setup

Install a dedicated GitHub App on this repository. Give it read access to repository administration,
metadata and Dependabot alerts, and read/write access to contents, issues, pull requests, workflows,
checks and commit statuses. Enable the dependency graph and Dependabot alerts for advisory-driven
pull requests. Use the scheduled runner as the sole Renovate installation managing Platform's
`renovate/` branches. [Renovate's GitHub App setup](https://docs.renovatebot.com/modules/platform/github/#running-as-a-github-app).

In **Settings → Secrets and variables → Actions**, set the repository variable
`DEPENDENCY_APP_CLIENT_ID` to the app's client ID and the secret `DEPENDENCY_APP_PRIVATE_KEY` to its
PEM private key. The workflow mints short-lived tokens for Platform. Commits from the app start PR CI
automatically. [GitHub workflow triggers](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

### Reviewing and publishing an update

1. Open the Renovate PR. The daily job refreshes affected Gradle locks and checksums, the backend stack
   snapshot and the pnpm lockfile. It adds the proposed Platform version and changelog to the same PR.
   Check the dependency diff, new checksums, advisory IDs for security fixes and the consumer-action notes.
2. Wait for CI on the prepared commit. A compatible update gets the next PATCH. An upstream major
   update or consumer-action marker gets the next MINOR with migration notes. Pending hand-written
   release notes require maintainer review. If another change reaches `main` first, run the daily
   workflow again to rebase the candidate before merging.
3. Merge the PR on GitHub. The [post-merge workflow](.github/workflows/dependency-release.yml)
   compares the merged tree with the reviewed head, creates the annotated version tag on the merge
   commit and dispatches `release.yml` at that tag. Full CI must pass before Maven or npm publication.
   If dispatch failed after tagging, rerun the post-merge job. A matching tag can be reused.
   If release verification itself fails, inspect the failed Release run before retrying.

## Cutting a release

1. Review the pinned actions. The daily workflow proposes their SHA and version comment together.
   When updating an action manually, pin the commit the
   tag points at, `gh api repos/<owner>/<repo>/commits/<tag> --jq .sha`, not the SHA of an annotated tag
   that `git ls-remote --tags` or `git/ref/tags` returns: the runner accepts both, but OpenSSF Scorecard
   rejects a tag object as an imposter commit and does not publish the result. The `action-pins` job of
   `ci.yml` runs `scripts/check-action-pins.sh`, which fails on such a pin and names the commit to use.
   If the GitHub API cannot resolve the tag, the check fetches that exact public tag over HTTPS
   and verifies its target commit. Missing tags and tags that do not resolve to a commit fail the check.
   `promote.yml` pins `deploy.yml` the same way ([ADR-0035](docs/adr/0035-promotion-by-commit-for-argo-cd.md)),
   so a change to `deploy.yml` reaches a promotion only when that pin moves. Run
   `git diff <pinned-sha> HEAD -- .github/workflows/deploy.yml`; if the change matters to a promotion, move the pin
   to the latest release that has it.
2. Run `scripts/consumer-audit.sh` to see which consumers and pins the release reaches
   (the report describes private repositories, so it stays local and never runs in CI), and who
   still calls a workflow it changes. Then decide on the notes. Pick the number by the
   [contract](docs/adr/0002-release-and-versioning-contract.md). Use a MAJOR for the change in distribution, a MINOR for consumer action within the same distribution, and a PATCH for a compatible change that requires no action. `release.sh` composes the `## [X.Y.Z] - YYYY-MM-DD` section of [CHANGELOG.md](CHANGELOG.md)
   from the commits since the previous tag unless you wrote it yourself (see step 4);
   `scripts/release-notes.sh v<previous>..HEAD` prints what it would compose. To write the notes by hand
   instead, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` and start a new empty `## [Unreleased]`
   above it; the section must have a `### Consumer action required` subsection, `None.` when nothing is
   required. The release script stamps a pending top row in the [compatibility matrix](docs/compatibility.md)
   with the version and release date.
3. Commit and push those changes through the normal branch and merge flow, so `main` equals
   `origin/main` with a clean tree.
4. Run the release helper and confirm the displayed version and notes.

```bash
./release.sh
```

With no arguments it uses the published tag for the current `platformVersion` and checks every
commit since that tag for consumer actions. A recorded action selects the next MINOR. Otherwise
it proposes the next PATCH. A prepared changelog section for the next PATCH or MINOR takes
precedence and must satisfy the same checks. Running it again at the released commit reports
that the tag already exists and finishes.

To supply your own release message, use `./release.sh "fix: short description"` for the next
patch, or `./release.sh "feat: publish under new coordinates" 3.0.0` for an explicit version.
The English Conventional Commit becomes the body of the release commit. Append `-y` after
an explicit version or set `ASSUME_YES=1` to skip confirmation.

The notes are the version's section of CHANGELOG.md. A hand-written `## [X.Y.Z] - YYYY-MM-DD` section is
used as it is. Without one, `release.sh` composes it with `scripts/release-notes.sh` from the commits since
the previous `vX.Y.Z` tag and inserts it under an empty `## [Unreleased]`, dated today: the first-parent
subjects (including the conventional PR title from a default GitHub merge) grouped as **Added** (`feat`), **Fixed** (`fix`) and **Changed** (every other type), and under
`### Consumer action required` the `Consumer-Action:` trailers of every commit in the range, the merge
commits of `./merge.sh` included, plus a `Breaking change: …` line for a commit without a trailer that has a
`!` in its subject or a `BREAKING CHANGE:` footer. A merge commit and the commits it brings in count as one change: a
trailer on either side replaces the `Breaking change:` line of the other, so a `!` repeated in the merge message
adds nothing. The same text from several commits (a trailer repeated in the merge message) is listed once, and
`None.` stands when there are none. When a maintainer merges `origin/main` locally, the
generator includes the incoming first-parent entries once if the merge applied exactly the
upstream file changes. A sync merge with additional edits requires manual release notes.
The release commit then carries CHANGELOG.md too.

Before it changes anything, `release.sh` refuses to run when:

- the working tree is not clean (untracked files included), the current branch is not `main`, or
  `HEAD` differs from `origin/main`;
- the release tags cannot be fetched from `origin`, for example because a local tag differs from the one on
  `origin` (it fetches them first, so the composed notes and the history check start at the latest release
  even when its tag was pushed after this clone fetched the commit);
- the message is not a Conventional Commit or contains Polish characters;
- the version's tag already exists;
- a hand-written section for the version has no `### Consumer action required` subsection;
- supplied arguments do not fit `"<message>" [X.Y.Z] [-y]`, for example a leftover `--skip-canary`;
- the section has to be composed, but CHANGELOG.md has no `## [Unreleased]` heading, has entries under
  it, or a first-parent subject since the previous tag is not a Conventional Commit (write the section
  by hand in those cases);
- the section has to be composed, but the newest `## [X.Y.Z]` section of CHANGELOG.md has no `vX.Y.Z` tag:
  that hand-written section is still unreleased, so release it first;
- the section has to be composed, but there are no commits since the previous tag;
- the release would be a patch although its section lists consumer action; the error names the
  MINOR version to use;
- the message is `feat`, uses `!:` or carries `BREAKING CHANGE`, and no version was given;
- a commit since the previous release's tag, a merge commit included, carries a
  `Consumer-Action: <what to do>` trailer, a `!` in its subject or a `BREAKING CHANGE:` footer, and the
  release would be a patch or its section says `None.`; the error lists those commits. Record a consumer
  action in the commit that causes it, as the pull request template asks, or in the `./merge.sh` message.
  This check and the composed section read the markers from one place,
  `scripts/release-notes.sh --markers`.

It then bumps `platformVersion` in every `gradle/*/gradle.properties` and
`templates/jvm/*/gradle.properties`, and `version` in every `frontend/packages/*/package.json`,
and commits them with the generated changelog section and any pending compatibility row.
It checks the branch, commit and working tree again after confirmation. It pushes the release
commit to `main` together with the annotated `vX.Y.Z` tag using `git push --atomic`.
If the remote rejects the push, both refs stay at their previous values. Inspect the rejection
and the remote refs before retrying the printed command for the prepared local commit and tag.
The tag message is the CHANGELOG section. The tree therefore always carries one
version; `templates/tests/platform-version-sync.test.sh` fails when a file drifts or a build script
falls back to a hard-coded version, and `templates/tests/release-script.test.sh` pins every
refusal above.

The `vX.Y.Z` tag starts `release.yml`; the trigger only matches `v*.*.*`.

To publish an existing tag again, run **Actions → Release (version tag) → Run workflow** on that
tag. A dispatch from a branch fails, because a release runs only from the tag that equals
`platformVersion`. Read the idempotency rules below first.

## What `release.yml` does

1. **`version`** reads `platformVersion` from `gradle/build-logic/gradle.properties` and fails
   unless the run started from the tag `v<platformVersion>`, so every published version has its
   tag and every tag has its version.
2. **`verify`** runs the full CI (`ci.yml`) on the tagged commit. It must be green before anything
   is published.
3. **`gradle`** and **`npm`** then run in parallel. One can fail while the other succeeds, so a
   release can be complete in one registry and missing in the other. Check both jobs before you
   announce a release. Each attests the files it publishes with `actions/attest`: SLSA build
   provenance for every jar and the catalog TOML the `gradle` job uploaded, and for every npm
   tarball, which the `npm` job packs, attests and then publishes, so the attested digest is the one
   in the registry. Consumers verify them as [docs/consuming.md](docs/consuming.md#verifying-provenance)
   shows.
4. **`github-release`**, also after both publish jobs, creates the GitHub Release `vX.Y.Z` titled
   "Platform X.Y.Z". Its notes are the version's CHANGELOG.md section, extracted by
   `scripts/changelog-section.sh`, plus a link to the diff from the previous version. A re-run
   leaves an existing Release alone.
6. **`verify-published`**, after both publish jobs, fails unless every artifact carries the
   version: the main build-logic artifact, the marker of every convention plugin, the package of every
   module in `gradle/maven-modules.txt` and every npm package not marked `private`. The publish jobs
   skip versions that already exist, so this is the one place that proves the release is complete.
7. **`verify-consumable`**, after `verify-published`, resolves the release the way a consumer does,
   from GitHub Packages with an empty Gradle home and no `-PplatformRepository`
   (`scripts/verify-consumable.sh`). Copies of the `java-library` and `spring-app` starters pinned to
   the version resolve the settings plugin, every convention plugin marker, the catalog's variant and
   test-fixtures; every public npm package installs at the version and ships the
   files its `main`, `bin` and `exports` name. Each resolution gets one retry, and the job summary
   lists every npm integrity. A failure points at [the rollback runbook](docs/runbooks/rollback.md).
8. **`release-assets`**, after `github-release`, attaches the release as files to the GitHub Release
   (`scripts/release-assets.sh`): `platform-maven-repo-X.Y.Z.zip`, a Maven repository of every module
   in `gradle/maven-modules.txt` published to a local directory, the npm tarballs packed from the registry, and
   `SHA256SUMS`, all attested, with the attestation's Sigstore bundle as
   `platform-X.Y.Z-assets.sigstore.json`, the signature file OpenSSF Scorecard's Signed-Releases check looks
   for. **`verify-bundle`** then builds the `spring-app` starter from the zip
   alone, with an empty Gradle home and no `GITHUB_TOKEN`
   ([README](README.md#try-it-without-credentials)).

A red job stops every job after it. A tag on a commit with red CI publishes nothing and
creates no GitHub Release.

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
- otherwise the package is packed with `pnpm pack`, and once every tarball is attested, published
  with `npm publish <tarball>`; a version-conflict response (`E409`, `409 Conflict`,
  `cannot publish over`) is treated as already published;
- any other failure marks the job failed, but the remaining packages are still attempted.

An npm package is published in a single request, so re-running the job after a partial failure is
safe: it publishes only the packages that are still missing.

## Merge messages and pull request titles

`scripts/merge.sh` (`./merge.sh` in Platform) refuses a merge message that is not a Conventional Commit, as
`release.sh` does: the merge commits on `main` are what `scripts/release-notes.sh` turns into the next
section. The `pr-title` job of `ci.yml` checks a pull request title against the same pattern. It stays an
advisory check, not a required one in the `main` ruleset: the owner integrates by direct push (`./merge.sh`, then
`git push`) and `release.sh` pushes its release commit, and a required status check would reject every such push,
because a commit made locally never carries a `pr-title` run.
`scripts/release-notes.sh v<previous>..HEAD` shows the next section and any `Consumer-Action:` trailer before
`./release.sh`.

## Support policy

Platform has one release line, `main`; there are no backport branches. So:

- Only the latest MINOR receives fixes. A fix to an older release is a new release on top of `main`.
- A consumer pin may stay at most **3 releases or 60 days** behind the latest release, whichever comes
  first.
- A release whose CHANGELOG section names a security fix must be adopted within **14 days**.

Consumers see the window without any network call. `seniordev.settings-conventions` logs one line per build
when its release is older than 60 days, and `platform-versions-check` prints the same line for a frontend
canon (from `releasedAt`, which `release.yml` stamps into the published `versions.json`). Both use the date
of the tagged commit, so the artifacts stay reproducible. The notice never fails a build: a time-based gate
would make old commits impossible to rebuild. Silence it with `-Pplatform.staleness.notice=false` or
`PLATFORM_STALENESS_NOTICE=false`.

## Consumers: adopting a new version

For a consumer on 1.x switching to 2.0.0, first [install the organization launcher](docs/consuming.md#move-a-1x-consumer-to-200).
For subsequent updates within the same major version, run the launcher from the consumer root.

```bash
./scripts/platform-bump.sh
```

Without an argument the script bumps to the newest release of the consumer's current MAJOR
version; when a newer MAJOR exists it says so and leaves crossing it to an explicit version. Pass
a version (`./scripts/platform-bump.sh 2.0.0`) to pin a specific one. It is a stub that calls the
`platform-bump` bin of `@seniordeveloper-pl-dominik-sienkiewicz/versions`, reads its token from `GPR_TOKEN`,
`GITHUB_TOKEN` or `gpr.key`, and:

- stops with exit code 2 before writing anything when a tool it needs is missing (`git`, `curl`,
  `python3`, `node` and `npm` for a frontend, a working `backend/gradlew` for a backend), when a
  file it rewrites has uncommitted changes (`--allow-dirty` overrides), or when GitHub rejects the
  token or reports a classic token without `read:packages`;
- skips the releases listed in [`releases/yanked.txt`](releases/yanked.txt) when it picks the
  newest one, and refuses an explicit yanked target unless `--allow-yanked` is passed; when the
  list cannot be read it warns and goes on;
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
- moves every `uses: SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/.github/workflows/<name>.yml@<ref>` in
  `.github/workflows/` to the target tag, a legacy `@v1` included, and so does a `platform-ref:` input of a
  `promote.yml` caller; a reference by commit SHA stays;
- verifies the attestation of the downloaded versions package with `gh attestation verify`, tied to the release's
  publishing workflow. A 2.0.0 bootstrap requires the organization workflow signature and
  the checksum. A missing verifier or an unsuccessful check stops the bootstrap;
- runs the upgrade migrations of the target release (`frontend/packages/versions/migrations/`) from
  the downloaded package, so it always applies the target's logic: each migration whose `SINCE` lies
  after the current pin and up to the target, and the `every-*` ones on every bump. It prints which it
  applied, skipped or left for a manual fix;
- checks every caller of a Platform reusable workflow against the target's caller contract with
  `platform-workflows-check`: the permissions it grants, its inputs and its secrets. It reports
  `ERROR` and `WARN` lines and does not fail the bump; run it on its own (exit 1 on an error) to
  gate a pull request;
- moves an older Gradle wrapper up to the catalog's `gradle` version of the target release, with the
  distribution's SHA-256, and keeps a newer one;
- regenerates `gradle.lockfile` and, when the repository verifies dependencies,
  `gradle/verification-metadata.xml`;
- lists the local version overrides in the backend's Gradle scripts (`useVersion`, `force`,
  `strictly`, `extra["….version"]`) that the Platform BOMs do not see, without failing.

If any step fails, the script restores every file it had changed, so the tree is as before the
bump. `--dry-run` prints the lines the bump would change, including the frontend canon and the
workflow references, then restores them; it runs neither npm install nor Gradle.

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

Old versions are never pruned automatically, neither in `release.yml` nor on a schedule, and Platform has no
cleanup tool. The support rule is: **no version that a consumer still pins may be deleted**, and a consumer
stays on a deleted version only by accident. When a deletion is needed, do it by hand in the package settings
on GitHub after reading the Platform pin column of `scripts/consumer-audit.sh`, and keep every version a
consumer still pins. GitHub can restore a deleted package
version for 30 days; after that it is gone.
