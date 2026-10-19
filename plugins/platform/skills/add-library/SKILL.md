---
name: add-library
description: "Add a new library or dependency to a repository that consumes Platform. Use when the user wants to add, introduce or upgrade a JVM library (a Gradle dependency, libs.versions.toml, a libs alias) or an npm package of the frontend, or when platformDependencyCheck or platform-versions-check rejects a version that is not in the canon."
---

# Add a library to a consumer

This skill holds no procedure. The procedure is a runbook, chosen by the kind of library, read at the release this
repository pins so the steps match the pin:

- a JVM library, a Gradle dependency: `docs/runbooks/add-jvm-library.md`
- an npm package of the frontend: `docs/runbooks/add-frontend-dependency.md`

1. Read the pinned Platform version: `platformVersion` in `backend/gradle.properties` or `gradle.properties`, or the
   version in the `platform-agents` marker of `AGENTS.md`.
2. Open the runbook that fits the library at that tag and follow it as written:
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/add-jvm-library.md`
   `https://github.com/DominikSienkiewicz/Platform/blob/v<version>/docs/runbooks/add-frontend-dependency.md`
3. If that page does not exist, the pin predates the runbook. Say so, and read the same file on `main` instead
   (replace `v<version>` with `main`); it may describe a newer release than the pin.
