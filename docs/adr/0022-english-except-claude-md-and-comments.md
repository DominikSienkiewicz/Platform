# ADR-0022: English everywhere, Polish only in CLAUDE.md and in code comments

## Status

Accepted — 2026-10-19

## Context

The maintainer writes in Polish; the consumers' agents, the reviewers of a public showcase and the messages a
consumer reads are better served in English. Mixed languages in one document made both readers skip parts.

## Decision

Polish only in `CLAUDE.md` and in comments of code and workflows; everything else in English: the README, `docs/`,
`RELEASING.md`, template READMEs, package descriptions, workflow input descriptions and every gate message
(Decision 8). `AGENTS.md` is the English, tool-neutral counterpart of `CLAUDE.md`.

## Consequences

- A consumer's build output and documentation are English.
- Two language registers coexist in the repository on purpose, which the README states.

## Revisit when

A second maintainer who does not read Polish joins.
