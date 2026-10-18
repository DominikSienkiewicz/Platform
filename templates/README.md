# templates — canonical shared files (source of truth)

Files that **cannot** be distributed through a registry, because each repository keeps its own
copy, but that have one source of truth here. To change one: edit it here, then sync it to the
consumer repositories.

The files a consumer keeps byte for byte are listed in [`manifest.json`](manifest.json). The
`platform-templates-check` bin of `@dominiksienkiewicz/versions` compares a repository's copies with
the canon of its pinned release and prints `DRIFT` or `MISSING` with the `curl` command that restores
each file; `platform-bump` runs it after every bump. It only reports and always exits 0. Run it by
hand from the repository root with `frontend/node_modules/.bin/platform-templates-check`.

| File | Purpose | Copy to |
|---|---|---|
| `jvm/java-library/`, `jvm/spring-app/` | minimal projects that consume the published plugins and catalog; built by Gradle TestKit. `java-library` carries the Gradle wrapper, and Platform's CI runs the reusable `backend-ci.yml` on it. Their `.gitignore` is the rules of `gitignore/root.gitignore` followed by `gitignore/backend.gitignore` | the root of a new repository; see [consuming.md](../docs/consuming.md) |
| `agent-gradle.sh` | opt-in worker limits with `AI_AGENT=1/true`; runs `./gradlew` from the root, or `backend/gradlew` from `backend/` when the root has no wrapper | `<repo>/scripts/agent-gradle.sh` |
| `.editorconfig` | consistent IDE style (Java: 2 spaces like google-java-format; Kotlin/`*.kts`: tabs) | the root of every repository |
| `.sdkmanrc` | the local JDK that runs Gradle, through SDKMAN (`sdk env`) | the root of every repository |
| `npmrc` | GitHub Packages registry and token lines for `@dominiksienkiewicz/*` | `<repo>/frontend/.npmrc` |
| `gitignore/root.gitignore` | OS, IDE, env files, `.secrets.local`, logs | `<repo>/.gitignore` |
| `gitignore/backend.gitignore` | Java and Gradle, IntelliJ (`out/`) and Buildship (`bin/`) output | `<repo>/backend/.gitignore` |
| `gitignore/frontend.gitignore` | Next.js, Node, Playwright | `<repo>/frontend/.gitignore` |
| `Dockerfile.backend` | runtime-only image (the `bootJar`) on `sapmachine:27-jre`; why, and when to move back to Temurin, is in [`../docs/versions.md`](../docs/versions.md) | `<repo>/backend/Dockerfile` |
| `platform-bump.sh` | **stub** that runs the `platform-bump` bin of `@dominiksienkiewicz/versions` (`frontend/node_modules/.bin`); the bump logic lives in the npm package, so the stub cannot drift. Needs `@dominiksienkiewicz/versions` 1.3.8 or newer | `<repo>/scripts/platform-bump.sh` |
| `bump-version.sh` | bumps the application version (`backend`/`frontend`) and creates a Liquibase changeset (`db new-migration`); not the same as `platform-bump.sh` | `<repo>/scripts/bump-version.sh` |
| `merge.sh` | safe integration of a local feature branch with a required merge message: preflight of the worktree (ignored files included) and the local target, freshness of `origin/<target>`, a lock against parallel runs, `--dry-run`, an explicit `--offline` mode, atomic cleanup, and a clear result: a green `✓` on success, a red `✗` on any failure (`NO_COLOR` disables colour, `FORCE_COLOR` forces it outside a terminal) | `<repo>/scripts/merge.sh` |
| `setup-gh-deploy.sh` | bootstraps the Actions secrets and variables of the reusable `deploy.yml` from a local `.secrets.local` (safe parser, values through stdin, `SSH_KNOWN_HOSTS` from ssh-keyscan, verified against `SSH_HOST_KEY_SHA256` when set; options `--gen-key`, `--with-release`); refuses to run when git does not ignore `.secrets.local`, and exits non-zero when a `gh` call fails | `<repo>/scripts/setup-gh-deploy.sh` |
| `secrets.local.example` | template of the local value file for `setup-gh-deploy.sh`; the secret and variable names are the contract of the reusable deploy | `<repo>/.secrets.local.example` |
| `grype.yaml` | accepted Grype findings, each with an expiry, a tracking link and a reason ([docs/security-scanning.md](../docs/security-scanning.md)) | `<repo>/.grype.yaml` |
| `manifest.json` | the copies `platform-templates-check` compares, each `source` here with its `target` in a consumer; `optional` files are compared only where the repository has them | not copied |
| `roadmap/` | **roadmap → Issues and Projects v2 toolkit** (subtree): the canonical logic (`roadmap-{to-issues,unblock,project-setup}.sh` and `lib/`) plus a per-repository `roadmap-config.sh`. Details and rollout in [`roadmap/README.md`](roadmap/README.md) | `<repo>/scripts/**` (config: `scripts/lib/roadmap-config.sh`) |
| `github/CODEOWNERS` | the default owner of the whole repository | `<repo>/.github/CODEOWNERS` |
| `github/pull_request_template.md` | pull request description template (purpose and checklist) | `<repo>/.github/pull_request_template.md` |

Tests of the template scripts live in `templates/tests/` and run in CI (the "Templates" job).
Platform uses the canonical `templates/merge.sh` through the thin delegate [`../merge.sh`](../merge.sh),
so its own copy of the helper cannot drift from the canon.

CI (reusable workflows), versions (catalog), quality (convention plugins), the linter config, the
frontend packages and the Renovate preset are distributed automatically (artifacts and `extends`),
so they are not here.

Project concepts, feature proposals, plans, and audits belong in local
`docs/concepts/`. The root Git ignore templates exclude that directory;
maintained technical documentation elsewhere under `docs/` stays versioned.
