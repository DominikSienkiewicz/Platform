# Building and publishing locally

## Bootstrap

Frontend requirements: Node.js ≥ 22.13 (this repository is built with Node 24) and pnpm
11.18.0.

```bash
# Gradle — publish to the local repository (a smoke test that needs no registry):
cd gradle/build-logic && ./gradlew publishToMavenLocal
cd ../catalog        && ./gradlew publishToMavenLocal

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

The rule is: **locally, consume what was built locally; after a push and on CI, consume the
published artifacts.**

| Layer | Locally, without GitHub | CI / after push |
|---|---|---|
| Gradle (plugins + catalog) | `mavenLocal()` comes first, so after `publishToMavenLocal` the build resolves locally. The GitHub repository is **not even added** when `gpr.user` / `gpr.key` are absent | `GITHUB_ACTOR` / `GITHUB_TOKEN` are present, so GitHub Packages is added as a fallback |
| npm (frontend packages) | `npm run platform:link` symlinks to `../../Platform/frontend/packages/*` — the live local source | dependencies resolve from the registry at `^1.0.0` |

```bash
# Once, in the platform — builds and publishes locally (Gradle → mavenLocal, frontend → pnpm install):
./buildAndPublishLocal.sh                  # (--skip-frontend / --with-registry / --help)

# In a consuming frontend repository:
npm run platform:link     # before working locally
npm run platform:unlink   # before committing — restores registry versions
```

> Gradle local-first is automatic: repository order plus absent credentials means GitHub is
> never contacted. npm has no native local-first-with-fallback, so local work uses
> `npm link` (Verdaccio would give full transparency). CI always publishes to and consumes
> from GitHub Packages.
