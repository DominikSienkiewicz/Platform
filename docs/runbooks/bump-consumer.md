# Bump a consumer

**Preconditions:** a clean working tree, a classic token with `read:packages` (`gpr.key` in
`~/.gradle/gradle.properties`, or `GITHUB_TOKEN`), JDK 25 for Gradle.

1. Preview the impact: `scripts/platform-bump.sh --dry-run --report`.
2. Read the release notes and the "Consumer action required" items it prints; apply each one.
3. Bump: `scripts/platform-bump.sh` (or `scripts/platform-bump.sh X.Y.Z` for a specific release). Without
   `frontend/`, the stub runs the bin of the release assets.
4. Run the gate: `AI_AGENT=1 bash scripts/agent-gradle.sh lint`, and in `frontend/` `npm ci` and
   `npx platform-versions-check`.
5. Move project rules that sit inside the Platform markers of `AGENTS.md`, `backend/AGENTS.md` or
   `frontend/AGENTS.md` out of them, and delete sections that only restate the stack the blocks now carry.
6. Commit the diff the bump left; it commits nothing itself.

**Done when:** `frontend/node_modules/.bin/platform-doctor --gradle` reports every PD check as OK, or, without a
frontend, `./gradlew platformDoctor` does.
