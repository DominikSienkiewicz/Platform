---
name: test-unreleased-change
description: "Test an unreleased Platform change on a consumer repository. Use when the user wants to preview a Platform branch or local change on a consumer before it is released, run the canary, or build a consumer with -PplatformRepository."
---

# Test an unreleased Platform change on a consumer

This skill holds no procedure. The procedure is the runbook `docs/runbooks/test-unreleased-change.md`, read at the
release this repository pins, so the steps match the pin.

1. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
2. Open the runbook at that tag and follow it as written:
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/test-unreleased-change.md`
3. If that page does not exist, the pin predates the runbook. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
