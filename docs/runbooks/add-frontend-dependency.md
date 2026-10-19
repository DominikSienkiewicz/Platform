# Add a frontend dependency

**Preconditions:** the package is needed by a consumer frontend and has no entry in the canon.

In Platform:

1. Add `"<package>": "<exact version>"` to `frontend/packages/versions/versions.json`.
2. Run the package tests in `frontend/packages/versions` (`npm test`) when asked, and note the entry in
   `CHANGELOG.md`; then release ([cut a release](cut-release.md)).

In the consumer:

3. `scripts/platform-bump.sh X.Y.Z` to that release.
4. Add the package to `frontend/package.json` at exactly the canon version, then `npm install --package-lock-only`.
5. Run `npx platform-versions-check`.

**Done when:** `npx platform-versions-check` prints "platform-versions-check: OK".
