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
| `agent-gradle.sh` | opt-in worker limits with `AI_AGENT=1/true`, and machine-wide slots (`AI_AGENT_TEST_SLOTS`, default 3) for runs of `test`, `integrationTest`, `check` or `build` across separate invocations; runs `./gradlew` from the root, or `backend/gradlew` from `backend/` when the root has no wrapper | `<repo>/scripts/agent-gradle.sh` |
| `agent-preflight.sh` | how many agents the machine holds right now, from free memory and swap on macOS or Linux: exit 0 go, 1 reduce (prints the number), 2 stop; thresholds overridable through env | `<repo>/scripts/agent-preflight.sh` |
| `.editorconfig` | consistent IDE style (Java: 2 spaces like google-java-format; Kotlin/`*.kts`: tabs) | the root of every repository |
| `.sdkmanrc` | the local JDK that runs Gradle, through SDKMAN (`sdk env`) | the root of every repository |
| `npmrc` | GitHub Packages registry and token lines for `@dominiksienkiewicz/*` | `<repo>/frontend/.npmrc` |
| `gitignore/root.gitignore` | OS, IDE, env files, `.secrets.local`, logs | `<repo>/.gitignore` |
| `gitignore/backend.gitignore` | Java and Gradle, IntelliJ (`out/`) and Buildship (`bin/`) output | `<repo>/backend/.gitignore` |
| `gitignore/frontend.gitignore` | Next.js, Node, Playwright | `<repo>/frontend/.gitignore` |
| `Dockerfile.backend` | runtime-only image (the `bootJar`) on `sapmachine:27-jre`; why, and when to move back to Temurin, is in [`../docs/versions.md`](../docs/versions.md) | `<repo>/backend/Dockerfile` |
| `Dockerfile.frontend` | Next.js standalone image on `node:24-slim`: `npm ci --ignore-scripts` with the token as the BuildKit secret `github_token` only, a non-root runner and `server.js`; needs the standalone output of `frontend/next.config.ts` | `<repo>/frontend/Dockerfile` |
| `frontend/next.config.ts` | `output: "standalone"`, which `Dockerfile.frontend` copies | `<repo>/frontend/next.config.ts` |
| `platform-bump.sh` | **stub** that runs the `platform-bump` bin of `@dominiksienkiewicz/versions` (`frontend/node_modules/.bin`); the bump logic lives in the npm package, so the stub cannot drift. Needs `@dominiksienkiewicz/versions` 1.3.8 or newer | `<repo>/scripts/platform-bump.sh` |
| `bump-version.sh` | bumps the application version (`backend`/`frontend`) and creates a Liquibase changeset (`db new-migration`); not the same as `platform-bump.sh` | `<repo>/scripts/bump-version.sh` |
| `merge.sh` | safe integration of a local feature branch with a required merge message: preflight of the worktree (ignored files included) and the local target, freshness of `origin/<target>`, a lock against parallel runs, `--dry-run`, an explicit `--offline` mode, atomic cleanup, a warning (not a refusal) when the source re-applies commits already on the target, and a clear result: a green `✓` on success, a red `✗` on any failure (`NO_COLOR` disables colour, `FORCE_COLOR` forces it outside a terminal) | `<repo>/scripts/merge.sh` |
| `worktree-new.sh` | starts a feature branch in its own worktree: `<type>/<description>-YYYY-MM-DD` (local date, `-2`… on a collision) in `.worktrees/` from the latest `origin/main`, with `/.worktrees/` in `.git/info/exclude`; the start of the lifecycle `merge.sh` ends | `<repo>/scripts/worktree-new.sh` |
| `worktree-status.sh` | every worktree under `.worktrees/` with its branch, commits ahead and behind the base, uncommitted files and whether `merge.sh` can take it | `<repo>/scripts/worktree-status.sh` |
| `setup-gh-deploy.sh` | bootstraps the Actions secrets and variables of the reusable `deploy.yml` from a local `.secrets.local` (safe parser, values through stdin, `SSH_KNOWN_HOSTS` from ssh-keyscan, verified against `SSH_HOST_KEY_SHA256` when set; options `--gen-key`, `--with-release`); creates the `production` environment limited to the `release` branch, keeps the `SSH_*` secrets there and lists repository-level copies to delete; refuses to run when git does not ignore `.secrets.local`, and exits non-zero when a `gh` call fails | `<repo>/scripts/setup-gh-deploy.sh` |
| `secrets.local.example` | template of the local value file for `setup-gh-deploy.sh`; the secret and variable names are the contract of the reusable deploy | `<repo>/.secrets.local.example` |
| `grype.yaml` | accepted Grype findings, each with an expiry, a tracking link and a reason ([docs/security-scanning.md](../docs/security-scanning.md)) | `<repo>/.grype.yaml` |
| `manifest.json` | the copies `platform-templates-check` compares, each `source` here with its `target` in a consumer; `optional` files are compared only where the repository has them | not copied |
| `roadmap/` | **roadmap → Issues and Projects v2 toolkit** (subtree, *experimental*: only its marker contract is stable): the canonical logic (`roadmap-{to-issues,unblock,project-setup}.sh` and `lib/`) plus a per-repository `roadmap-config.sh`. Details and rollout in [`roadmap/README.md`](roadmap/README.md) | `<repo>/scripts/**` (config: `scripts/lib/roadmap-config.sh`) |
| `github/CODEOWNERS` | the default owner of the whole repository | `<repo>/.github/CODEOWNERS` |
| `github/pull_request_template.md` | pull request description template (purpose and checklist) | `<repo>/.github/pull_request_template.md` |

Tests of the template scripts live in `templates/tests/` and run in CI (the "Templates" job).
Platform uses the canonical `templates/merge.sh`, `worktree-new.sh` and `worktree-status.sh` through thin
delegates in its root ([`../merge.sh`](../merge.sh)), so its own copies of the helpers cannot drift from the canon.

CI (reusable workflows), versions (catalog), quality (convention plugins), the linter config, the
frontend packages and the Renovate preset are distributed automatically (artifacts and `extends`),
so they are not here.

Project concepts, feature proposals, plans, and audits belong in local
`docs/concepts/`. The root Git ignore templates exclude that directory;
maintained technical documentation elsewhere under `docs/` stays versioned.
