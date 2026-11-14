---
name: tdd-bugfix
description: "Fix a reported bug in a consumer repository by writing a regression test that reproduces it first, watching it fail, then making the smallest fix in one fix: commit that the red-proof job of backend-ci can prove. Use when the user reports a bug, a wrong result, an exception or a regression, or asks for a fix: commit."
---

# Fix a bug test-first

This skill holds no procedure. The procedure is the runbook `docs/runbooks/tdd-bugfix.md`, read at the release this
repository pins, so the steps match the pin.

1. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
2. Open the runbook at that tag and follow it as written:
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/tdd-bugfix.md`
3. If that page does not exist, the pin predates the runbook. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
