# ADR-0002: Release and versioning contract

## Status

Accepted — 2026-10-18

## Context

Platform publishes Gradle convention plugins, a version catalog, test fixtures, a security
starter, npm packages and reusable workflows, and five product repositories consume them. Up
to 1.5.31 the release process had mechanics but no contract:

- `release.sh` defaulted to a patch, so changes that required consumer action shipped as
  patches. 1.5.29 moved the toolchain to JDK 27, which forced every consumer to change its
  runtime image. 1.5.31 made `backend-ci.yml` require `packages: read`, which broke a caller
  that did not grant it. The equivalent toolchain move 25 → 26 had been a minor (1.4.0).
- Nothing carried change information: no changelog, no GitHub Releases, lightweight tags with
  messages such as "ci fix", and release commits whose subject named a feature instead of the
  version.
- The release published before CI on the tagged commit finished, and the moving `v1` tag
  changed reusable workflows for every caller at once, whatever version the caller pinned.

The owner settled the open questions on 2026-10-16 (decisions 2, 3, 4 and 5 of the audit
backlog). This ADR records them as one contract.

## Decision

1. **One version.** Every artifact, Maven and npm, is published at one `platformVersion`.
   Every version file in the tree carries it (`gradle/*/gradle.properties`,
   `templates/jvm/*/gradle.properties`, `frontend/packages/*/package.json`), and `release.sh`
   bumps them all.
2. **Immutable and gated.** A version is never republished with different content. A release
   runs only from the tag that equals `platformVersion`, and only after the full CI passes on
   the tagged commit. Publication is idempotent per registry.
3. **Numbering.** In the 1.x line:
   - a change that requires **consumer action** bumps the **MINOR** version;
   - every other change is a **PATCH**;
   - **MAJOR** is reserved and is not used in the 1.x line.

   This deviates from strict semantic versioning on purpose. Consumers pin exact versions and
   take a release only through `platform-bump`, which shows them the required action. MINOR
   therefore means "read the notes and act before or while you bump". MAJOR stays free for a
   change of the distribution model itself, such as a new registry or new artifact coordinates.
4. **Consumer action** is anything a consumer must do beyond bumping the pin:
   - a toolchain or runtime change (JDK, runtime image, a JDK needed on CI);
   - a new or tightened gate that can turn a consumer build red;
   - a removed or renamed catalog alias, property, task, knob or convention behaviour;
   - a new or removed workflow input, permission or secret, or a changed default.
5. **Release notes.** `CHANGELOG.md` is the single source. Every version has a
   `## [X.Y.Z] - YYYY-MM-DD` section with a mandatory `### Consumer action required`
   subsection, which says "None." when nothing is required. `release.sh` refuses a version
   without a section and a patch whose section lists consumer action, and it writes the section
   into the annotated version tag. `release.yml` creates the GitHub Release from the same
   section, and `platform-bump` prints the notes of every release it crosses.
6. **Reusable workflows.** Consumers reference reusable workflows by the exact `@vX.Y.Z` of
   their pin, so workflow logic and artifacts come from one release and roll back together.
   The moving `v1` tag keeps moving forward, after both publications succeed, only until every
   consumer has migrated; then the `move-v1` job is retired.
7. **Bump channel.** Consumers bump with `platform-bump` (a stub that runs the bin of
   `@dominiksienkiewicz/versions`); a reusable `platform-bump.yml` workflow will open the bump
   pull request. The Renovate preset is narrowed to GitHub Actions and Docker images.

| Class of change | Convention plugins | Catalog | Test fixtures, security starter | npm packages | Reusable workflows | Templates |
|---|---|---|---|---|---|---|
| Consumer action (item 4) | MINOR | MINOR | MINOR | MINOR | MINOR | MINOR |
| New opt-in capability, fix, dependency bump without action | PATCH | PATCH | PATCH | PATCH | PATCH | PATCH |
| Docs, tests or CI of Platform only | PATCH, or no release | — | — | — | — | — |
| Distribution model (registry, coordinates) | MAJOR | MAJOR | MAJOR | MAJOR | MAJOR | MAJOR |

Classified under this rule, 1.5.29 (toolchain 27, runtime image ≥ 27) and 1.5.31
(`packages: read` for `backend-ci.yml` callers) would have been minors.

## Consequences

- (+) The version number tells a consumer whether a bump needs attention, and the notes say
  what to do. Tooling can stop on it: `release.sh` refuses the patch, `platform-bump` prints
  the action.
- (+) A red commit can no longer reach the registry, and a published version has its tag and
  its notes.
- (−) Every release needs a hand-written CHANGELOG section. Whether a change needs consumer
  action stays a human judgement, guided by item 4.
- (−) Minors become more frequent than in strict semantic versioning.

## Revisit when

- Every consumer references reusable workflows by `@vX.Y.Z`: retire `move-v1` and drop item 6's
  transition clause.
- Platform changes its registry or artifact coordinates: that is the first MAJOR.

## Update — merge messages and the draft release (2026-10-19)

`scripts/merge.sh` refuses a merge message that is not a Conventional Commit, the rule `release.sh` already applies
to its message, because the merge commits on `main` are what `scripts/release-notes.sh` drafts the next section from.
`release-draft.yml` keeps a draft GitHub Release **Next** with those notes after every push to `main` (N-REL-7).
