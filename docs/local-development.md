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
