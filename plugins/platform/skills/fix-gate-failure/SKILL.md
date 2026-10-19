---
name: fix-gate-failure
description: "Fix a failed Platform gate in a consumer repository. Use when a build, lint or CI run fails with a code such as [PLAT-DEP-001] or [PLAT-FE-002], when platformDependencyCheck, platformPinCheck, platform-versions-check or platformDoctor is red, or when the user pastes a log that contains a PLAT- code."
---

# Fix a failed Platform gate

This skill holds no procedure. Every Platform gate names its failure with a code, and the section of that code in
`docs/gates.md` holds the cause and the fix for the release that produced it.

1. Find the `[PLAT-…]` code in the failure output, the CI annotations or the log the user pasted.
2. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
3. Open the section of the code at that tag, with the code in lower case as the anchor (`#plat-dep-001` for
   `PLAT-DEP-001`), and follow its Fix as written. The link in the failure message points at the same section.
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/gates.md#<code>`
4. If that page does not exist, the pin predates the gate codes. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
