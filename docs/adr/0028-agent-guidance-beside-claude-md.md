# ADR-0028: Agent guidance: AGENTS.md beside CLAUDE.md, and a managed block in consumers

## Status

Accepted — 2026-10-19

## Context

Each consumer restated Platform's rules for its agents in its own words, and the copies drifted. Platform itself
had only a Polish `CLAUDE.md`.

## Decision

- Platform keeps `CLAUDE.md` unchanged and adds a tool-neutral English `AGENTS.md` beside it (N-SHOW-1).
- `templates/agents/platform-block.md` is the Platform block of a consumer's `AGENTS.md`; `platform-bump` writes it
  between its markers with the target version and leaves the rest of the file alone.
- `docs/consumer-agents.md` and `docs/runbooks/` hold the rules and procedures the block links at the pinned tag;
  `templates/tests/agent-docs.test.sh` fails when they name a command, task, bin or path that does not exist.

## Consequences

- Consumers delete their copied sections at the next bump.
- 2026-10-19: the same mechanism manages `platform-agents-backend` in `backend/AGENTS.md` and
  `platform-agents-frontend` in `frontend/AGENTS.md`, with the stack of the pinned release, because the consumers'
  hand-copied per-directory files named versions two releases old. A missing `CLAUDE.md` beside them becomes a
  one-line `@AGENTS.md` import; per-stack starter files copied once were rejected, as they drift the same way.

## Revisit when

None.
