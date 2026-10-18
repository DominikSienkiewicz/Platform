# ADR-0006: pnpm in Platform's workspace, npm with a committed lockfile in consumers

## Status

Accepted — 2026-10-18

## Context

Platform builds its frontend packages in a pnpm workspace (`frontend/pnpm-workspace.yaml`,
`frontend/pnpm-lock.yaml`, pnpm 11.18.0 in `packageManager`), and `ci.yml` and `release.yml` install
with `pnpm install --frozen-lockfile`. The consumer side was settled differently, one tool at a time:
the reusable `frontend-ci.yml` runs `npm ci`, `sonar.yml` caches `frontend/package-lock.json`,
`security-scan.yml` scans `package-lock.json`, and `platform-bump` refreshes the consumer's lockfile
with npm. All four frontend consumers use npm. Nothing recorded why the two sides differ, so the
mismatch read as an accident, and a reader could not tell which one to change.

## Decision

- Platform keeps pnpm for its own workspace. It installs every package under `frontend/packages/`
  in one pass with one lockfile, and pnpm's strict node_modules layout makes a package fail when it
  imports a dependency it does not declare, before a consumer installs it.
- Consumers use npm with a committed `package-lock.json`. The reusable workflows and `platform-bump`
  support npm only; a consumer on pnpm or Yarn fails `frontend-ci`.
- The published packages carry no pnpm-specific fields (`workspace:` protocol, `pnpm` settings), so
  what a consumer installs with npm is what Platform tested.
- Versions on both sides come from one canon: `frontend/packages/versions/versions.json`, held for
  Platform's own manifests by `self-canon.test.mjs` and for consumers by `platform-versions-check`.

## Consequences

- Two lockfile formats to keep current: `pnpm install` regenerates Platform's, `platform-bump` the
  consumers'.
- A consumer that wants pnpm needs Platform to support it in `frontend-ci.yml`, `sonar.yml`,
  `security-scan.yml` and `platform-bump`, together, in a MINOR release.
- `docs/consuming.md` states the npm requirement next to the frontend setup.

## Revisit when

A consumer asks to move to pnpm, or npm stops being the package manager of every frontend consumer.
