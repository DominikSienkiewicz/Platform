# Contributing

Platform is a single-maintainer project, run in public as a showcase of how one shared layer keeps a set of
product repositories consistent. Issues are welcome: a bug, a library a consumer needs, or the adoption of an
incubating artifact each has a form. Pull requests are welcome **after an issue they implement has been agreed**;
an unannounced pull request may be closed without review, because every change here reaches several repositories.
Report a vulnerability privately, as [SECURITY.md](SECURITY.md) describes.

## Development setup

The [devcontainer](.devcontainer/devcontainer.json) has everything: JDK 25 to run Gradle, JDK 27 as the toolchain,
Node 24 and pnpm. Without it, follow [docs/local-development.md](docs/local-development.md).

## Rules a change must follow

- **Versions live in one place.** A JVM library or plugin version goes into `gradle/catalog/libs.versions.toml`, a
  frontend version into `frontend/packages/versions/versions.json`; nothing else carries a version literal. The
  hard rules are in [AGENTS.md](AGENTS.md).
- **One branch per change, in a worktree.** Work on `<type>/<description>-YYYY-MM-DD` under `.worktrees/`; the
  maintainer integrates it with `./merge.sh <branch> "<conventional commit message>"`.
- **Conventional Commits** for commit messages and pull request titles (`ci.yml` checks the title). Record what a
  consumer must do in a `Consumer-Action:` trailer and under `### Consumer action required` in `CHANGELOG.md`
  ([release contract](docs/adr/0002-release-and-versioning-contract.md)).
- **No AI attribution** in commits, pull requests or titles.
- **New functionality comes with tests** that cover it, in the same pull request.
- **A bug fix starts with a regression test** that fails without the fix. An existing test changes only when the
  contract it pins changes on purpose, and the pull request says why.
- **English** for everything except `CLAUDE.md` and code and workflow comments, which are Polish.
- **Documentation** that describes the changed behaviour changes in the same pull request.

## The gate

Run the formatter and the linters of what you touched before you open a pull request. In a Java module
(`gradle/test-fixtures`, the starters) that is `./gradlew format lint`; in the convention plugins:

```bash
cd gradle/build-logic && ./gradlew spotlessApply spotlessCheck
```

```bash
git ls-files -z '*.sh' | xargs -0 shellcheck -x --severity=warning
```

```bash
actionlint
```

The test suites (`./gradlew test` in a Gradle module, `pnpm test` in `frontend/`, `templates/tests/*.test.sh`)
run in CI; run the ones your change affects when you can. A gate failure names its code, explained in
[docs/gates.md](docs/gates.md).

## Code of conduct

Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).
