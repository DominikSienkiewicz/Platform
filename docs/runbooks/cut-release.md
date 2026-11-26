# Cut a Platform release

For a dependency update prepared by the daily workflow, review its version and changelog and merge
the PR on GitHub. The merge triggers release verification on the new tag.
[Daily dependency releases](../../RELEASING.md#daily-dependency-releases).

**Manual release preconditions:** `main` is green and equal to `origin/main`, and the working tree is clean.
`scripts/release-notes.sh v<previous>..HEAD` shows the notes since the last tag.

1. Optional: to write the notes by hand, turn `## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD` with a
   `### Consumer action required` section (`None.` when there is none), and merge that change the usual way.
   Without it, `release.sh` composes the section from the commits since the last tag.
2. Run `./release.sh` and review the proposed version and notes. The default is the next PATCH,
   or the next MINOR for recorded consumer actions. To choose a specific version, use
   `./release.sh "<conventional commit>" X.Y.Z`. Distribution changes require an explicit MAJOR.
3. Confirm the release. The helper commits the version files, any generated notes and the pending
   compatibility row. It pushes the release commit and annotated tag atomically.
   `release.yml` publishes after `ci.yml` is green on the tagged commit.

**Done when:** `release.yml` is green for the tag and the GitHub Release `vX.Y.Z` carries its assets.
