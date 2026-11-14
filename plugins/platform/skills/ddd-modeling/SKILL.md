---
name: ddd-modeling
description: "Model or reshape a domain in a consumer repository with Domain-Driven Design: the ubiquitous language, bounded contexts and their map, the choice between aggregate, value object, domain service and port with adapter, module boundaries that a test verifies, and an ADR for every pattern. Use when the user asks to design a domain, split a module, add an aggregate or an entity, draw a context map, or asks about DDD."
---

# Model a domain with DDD

This skill holds no procedure. The procedure is the runbook `docs/runbooks/ddd-modeling.md`, read at the release this
repository pins, so the steps match the pin.

1. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
2. Open the runbook at that tag and follow it as written:
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/ddd-modeling.md`
3. If that page does not exist, the pin predates the runbook. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
