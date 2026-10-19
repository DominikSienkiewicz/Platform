# devcontainer — a development container for a consumer repository

> **Incubating** (Decision 7). No product repository has adopted this template yet, and Platform's CI does not
> build it (only its own [`.devcontainer/`](../../.devcontainer/devcontainer.json) is built). Treat the files as
> provisional until the first consumer adopts them; that pull request removes this notice.

A container with everything a consumer repository builds with: the JDK that runs Gradle, the toolchain JDK of the
catalog, and Node with npm. It assumes the consumer layout: `backend/` with the Gradle wrapper and
`gradle/gradle-daemon-jvm.properties`, and optionally `frontend/` with a committed `package-lock.json`.

| File | Target in the consumer | Role |
|---|---|---|
| `Dockerfile` | `.devcontainer/Dockerfile` | base image pinned by digest next to its tag; Temurin for both JDKs and Node, each checked against a SHA-256 sum |
| `devcontainer.json` | `.devcontainer/devcontainer.json` | builds the image, runs as `vscode`, passes the GitHub Packages credentials through, runs `post-create.sh` |
| `post-create.sh` | `.devcontainer/post-create.sh` | registers the toolchain JDK for Gradle and installs the frontend dependencies |

Copy the three files from the release the repository pins (replace `vX.Y.Z`):

```bash
mkdir -p .devcontainer && for file in Dockerfile devcontainer.json post-create.sh; do
  curl -fsSL "https://raw.githubusercontent.com/DominikSienkiewicz/Platform/vX.Y.Z/templates/devcontainer/$file" -o ".devcontainer/$file"
done
```

## Versions come from the canon

The three `ARG`s of the `Dockerfile` are not a new source of truth.
[`templates/tests/consumer-devcontainer.test.sh`](../tests/consumer-devcontainer.test.sh) fails unless they equal:

| `ARG` | Canon |
|---|---|
| `GRADLE_JDK` | `toolchainVersion` of the daemon criteria in [`templates/jvm/*/gradle/gradle-daemon-jvm.properties`](../jvm/java-library/gradle/gradle-daemon-jvm.properties), which is the `java-version` default of `backend-ci.yml` |
| `TOOLCHAIN_JDK` | `java` in the [catalog](../../gradle/catalog/libs.versions.toml) |
| `NODE_MAJOR` | [`frontend/.nvmrc`](../../frontend/.nvmrc) |

`JAVA_HOME` is the first JDK; `post-create.sh` writes the second to `~/.gradle/gradle.properties` as
`org.gradle.java.installations.paths`, the way `ci.yml` registers it, so Gradle uses it as the toolchain instead of
asking Foojay for it. The three files are optional entries of [`manifest.json`](../manifest.json), so
`platform-templates-check` reports `DRIFT` when a repository's copy differs from the canon of its pinned release and
prints the `curl` command that restores it; a deliberate fork (extra extensions, say) can stay.

## Credentials

A token is never baked into the image or written to a file. `devcontainer.json` forwards two variables from the
environment that starts the container, with `remoteEnv`, so they exist only in the running container's processes:

| Variable | Value |
|---|---|
| `GITHUB_ACTOR` | your GitHub login |
| `GITHUB_TOKEN` | a classic token with `read:packages` |

These are the names `settings.gradle.kts` falls back to after `gpr.user` and `gpr.key`, and `frontend/.npmrc` reads, so
Gradle and npm need nothing else. Export both in the shell that starts the editor or the
`devcontainer` CLI, before the container is created or restarted.

Without a token, `post-create.sh` registers the toolchain JDK, prints a hint, and skips `npm ci` instead of failing.
Once the variables are set, rebuild the container, or restart it and run `npm ci --ignore-scripts` in `frontend/` by
hand. The script runs that command only when `frontend/package-lock.json` exists.

GitHub Codespaces is not covered: its built-in `GITHUB_TOKEN` is limited to the repository, and a secret cannot be
named `GITHUB_*`, so there is nothing to forward from.
