# ADR-0033: Prometheus is opt-in in the observability starter

## Status

Accepted — 2026-10-19

## Context

Metrics leak information about an application, and the security starter permits only health and info by
default.

## Decision

`platform.observability.prometheus=true` exposes `/actuator/prometheus`; `public-metrics` adds it to the security
starter's permitted paths for a scraper inside the network (Decision 37).

## Consequences

- A consumer exposes metrics on purpose.

## Revisit when

None.
