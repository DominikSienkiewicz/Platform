# Add a frontend dependency

**Preconditions:** the package is needed by a consumer frontend and has no entry in the canon.

**Decide first: frame or application.** The canon holds the frame only; a package outside it belongs to the
application ([ADR-0037](../adr/0037-platform-governs-the-frame.md)).

- Used by one repository: do not touch Platform. Add the package to `frontend/package.json` at an exact version,
  run `npm install --package-lock-only` and `npx platform-versions-check`. It leaves the package, and an override
  for it, alone.
- Used by two or more repositories: it belongs to the frame, so follow the steps below.

In Platform:

1. Add `"<package>": "<exact version>"` to `frontend/packages/versions/versions.json`.
2. Run the package tests in `frontend/packages/versions` (`npm test`) when asked, and note the entry in
   `CHANGELOG.md`; then release ([cut a release](cut-release.md)).

In the consumer:

3. `scripts/platform-bump.sh X.Y.Z` to that release.
4. Add the package to `frontend/package.json` at exactly the canon version, then `npm install --package-lock-only`.
5. Run `npx platform-versions-check`.

**Done when:** `npx platform-versions-check` prints "platform-versions-check: OK".
