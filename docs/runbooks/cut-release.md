# Cut a Platform release

**Preconditions:** `main` is green and equal to `origin/main`, and the working tree is clean.
`scripts/release-notes.sh v<previous>..HEAD` shows the notes since the last tag.

1. Optional: to write the notes by hand, turn `## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD` with a
   `### Consumer action required` section (`None.` when there is none), and merge that change the usual way.
   Without it, `release.sh` composes the section from the commits since the last tag.
2. Use `./release.sh "<conventional commit>" X.Y.Z` on the prepared `main`. For the npm scope
   and registry move, follow [First organization release](../../RELEASING.md#first-organization-release)
   with the explicit version `2.0.0` (MAJOR under ADR-0002). The helper commits the
   version files (and CHANGELOG.md when it composed the section), pushes `main` and pushes the annotated tag;
   `release.yml` publishes after `ci.yml` is green on the tagged commit.

**Done when:** `release.yml` is green for the tag and the GitHub Release `vX.Y.Z` carries its assets.
