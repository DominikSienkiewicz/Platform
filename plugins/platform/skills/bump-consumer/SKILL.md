---
name: bump-consumer
description: "Bump the Platform release a consumer repository pins. Use when the user asks to 'bump platform', update or upgrade Platform, move to a newer Platform release, run platform-bump, or fix a pin mismatch such as PLAT-PIN-001."
---

# Bump Platform in a consumer

This skill holds no procedure. The procedure is the runbook `docs/runbooks/bump-consumer.md`, read at the release
this repository pins, so the steps match the pin.

1. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
2. Open the runbook at that tag and follow it as written:
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/bump-consumer.md`
3. If that page does not exist, the pin predates the runbook. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
