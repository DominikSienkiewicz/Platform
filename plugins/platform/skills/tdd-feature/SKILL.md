---
name: tdd-feature
description: "Implement new behaviour test-first in a consumer repository: an acceptance criterion as Given/When/Then, a failing test observed by running only that test, the smallest code that turns it green, then a refactor. Use when the user asks to add or change a feature, an endpoint, a use case or a rule, asks for TDD or red-green-refactor, or wants one commit per behaviour."
---

# Build a feature test-first

This skill holds no procedure. The procedure is the runbook `docs/runbooks/tdd-feature.md`, read at the release this
repository pins, so the steps match the pin.

1. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
2. Open the runbook at that tag and follow it as written:
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/tdd-feature.md`
3. If that page does not exist, the pin predates the runbook. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
