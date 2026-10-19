# Building and publishing locally

## Bootstrap

Frontend requirements: Node.js ≥ 22.13 (this repository is built with Node 24) and pnpm
11.18.0.

```bash
# Gradle — publish all 4 modules to the local Maven repository (a smoke test that needs no registry):
./buildAndPublishLocal.sh --skip-frontend

# Frontend:
cd frontend && pnpm install
pnpm --filter @dominiksienkiewicz/ui build   # generates public/r/*.json (shadcn)
```

## GitHub Packages credentials

For Gradle, in `~/.gradle/gradle.properties` — not in the repository:

```properties
gpr.user=<github-login>
gpr.key=<PAT with read:packages / write:packages>
gpr.owner=DominikSienkiewicz
gpr.repo=Platform
```

For npm, pnpm 11 requires the token in a trusted `~/.npmrc`, not in the committed
`frontend/.npmrc`:

```properties
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

> For GitHub Packages npm the scope (`@dominiksienkiewicz`) must equal the repository
> owner, lowercased. A different owner means changing the scope in the packages and in
> `.npmrc`.

## Local-first: building without GitHub

The rule is: **locally, consume what was built locally, explicitly; after a push and on CI,
consume the published artifacts.** `-PplatformRepository` is the only official way to test an
unreleased Platform change on a consumer ([ADR-0003](adr/0003-local-platform-resolution.md));
no convention reads the local Maven repository implicitly.

| Layer | Locally, without GitHub | CI / after push |
|---|---|---|
| Gradle (plugins + catalog) | Run `./buildAndPublishLocal.sh`, then build the consumer with `-PplatformVersion=<version> -PplatformRepository=file://$HOME/.m2/repository`; the explicit local repository comes first | GitHub Packages uses `GITHUB_ACTOR` / `GITHUB_TOKEN` |
| npm (frontend packages) | `npm install --no-save <absolute path>/Platform/frontend/packages/<name>` installs the live local source without touching `package.json` | dependencies resolve from the registry at the exact Platform version |

```bash
# Once, in the platform — publishes the Gradle modules to ~/.m2/repository and installs the frontend:
./buildAndPublishLocal.sh                  # (--skip-frontend / --with-registry / --help)

# In a consuming backend (it prints this command with the version filled in):
./gradlew build -PplatformVersion=<version> -PplatformRepository=file://$HOME/.m2/repository

# In a consuming frontend; `npm ci` restores the registry versions afterwards:
npm install --no-save <absolute path>/Platform/frontend/packages/<name>
```

> This needs a consumer on Platform 1.5.31 or newer whose `pluginManagement` contains the
> `platformRepository` line of [`templates/jvm/spring-app/settings.gradle.kts`](../templates/jvm/spring-app/settings.gradle.kts);
> otherwise plugins still resolve from GitHub Packages. A missing local artifact may still need
> remote access.

### Previewing a change on a real consumer

`buildAndPublishLocal.sh` publishes under the released version, and on a real consumer that collides
with the published bytes, trips dependency verification and leaves literal pins untouched.
`scripts/preview-on-consumer.sh` avoids all of that:

```bash
scripts/preview-on-consumer.sh ../Azimuth
```

```bash
scripts/preview-on-consumer.sh ../Azimuth --gradle "check" --keep
```

It publishes every module of `gradle/maven-modules.txt` as `<next patch>-canary.<commit>`, a version no
release can have, to a temporary repository (`--staging <dir>` shares one repository across runs and
publishes into it once); checks the consumer's `HEAD` out in a throwaway worktree
(`<consumer>/.worktrees/platform-preview-<commit>`); rewrites its pins there with the same rules as
`platform-bump`; and runs Gradle with `-PplatformRepository`, an init script that adds the repository to
`pluginManagement` (so consumers that do not read `platformRepository` there work too), `--write-locks`
and `--dependency-verification=lenient`, which are acceptable only in that throwaway worktree. The
default tasks are `compileJava compileTestJava platformDependencyCheck`. The consumer's own checkout is
never touched, and the worktree is removed afterwards unless `--keep` is passed. `--frontend` also
checks the consumer's `frontend/`: it applies the canon of the working tree with
`platform-versions-check --fix` in the worktree and runs the check again, so what remains is what a bump
would not fix, such as a dependency without a canon entry.

`scripts/canary.sh` runs that preview with `--frontend` on every consumer of `scripts/consumers.txt`
and records the result for `HEAD`, which `release.sh` requires ([RELEASING.md](../RELEASING.md#cutting-a-release)).
