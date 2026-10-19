# Cut a Platform release

**Preconditions:** `main` is green and equal to `origin/main`, the working tree is clean, and the
`## [Unreleased]` section of `CHANGELOG.md` is complete. The draft release **Next** (`release-draft.yml`) shows
the notes since the last tag.

1. `scripts/canary.sh` on every consumer; a release without a PASS for `HEAD` needs
   `--skip-canary "<reason>"`.
2. Turn `## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD` with a `### Consumer action required` section
   (`None.` when there is none), and merge that change the usual way.
3. `./release.sh "<conventional commit>" X.Y.Z` (a consumer action needs a MINOR; ADR-0002). It commits the
   version files, pushes `main` and pushes the annotated tag; `release.yml` publishes after `ci.yml` is green
   on the tagged commit.
4. Roll it out: `scripts/ring-rollout.sh X.Y.Z` (Touchstone first).

**Done when:** `release.yml` is green for the tag and the GitHub Release `vX.Y.Z` carries its assets.
