# ADR-0027: Gate codes are a public contract

## Status

Accepted — 2026-10-19

## Context

Gate messages were free text: an agent or a person could not look a failure up, and a reworded message broke
every search for it.

## Decision

- Every Platform gate names its failure with a stable `PLAT-<area>-<nnn>` code and a link to its section of
  `docs/gates.md` at the release that produced it; a retired code is never reused.
- The `platform-doctor` IDs (`PD0xx`) stay a separate contract (N-SHOW-8).
- `templates/tests/gate-codes.test.sh` fails on a code without a section, or a section without a code.

## Consequences

- A failure in a consumer's log points at the rules of the release it pins.

## Revisit when

None.
