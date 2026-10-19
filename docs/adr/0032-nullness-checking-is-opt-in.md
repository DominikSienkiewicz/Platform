# ADR-0032: Nullness checking is opt-in

## Status

Accepted — 2026-10-19

## Context

NullAway with JSpecify catches null dereferences at compile time, but Error Prone hooks into javac internals and
has lagged new JDKs, and Platform compiles on the non-LTS JDK 27.

## Decision

`seniordev.nullness-conventions` applies Error Prone with NullAway in JSpecify mode, checking only packages marked
`@NullMarked`; it is a separate, opt-in plugin, verified on the canon toolchain by TestKit (N-CAP-11).
`seniordev.java-conventions` compiles with `-Xlint:all,-processing,-serial`, and `platform.javac.werror=true` is the
ratchet that turns warnings into errors.

## Consequences

- A toolchain bump never waits for Error Prone in a repository that does not use it.

## Revisit when

Every consumer applies it: then it can move into `seniordev.java-conventions`.
