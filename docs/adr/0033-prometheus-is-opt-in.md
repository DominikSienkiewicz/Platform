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

## Update — no security starter (2026-11-20)

Platform 1.13.0 removes `platform-security-starter`, and with it `platform.observability.public-metrics`, which only
added `/actuator/prometheus` to that starter's permitted paths. `platform.observability.prometheus` stays opt-in; who
may read the endpoint is the application's own security configuration.
