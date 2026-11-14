# Contributing

This project is maintained by one person and run in public. Issues are welcome: a bug, a feature request or a
question each has a form. Pull requests are welcome **after an issue they implement has been agreed**; an
unannounced pull request may be closed without review. Report a vulnerability privately, as the
[security policy](https://github.com/DominikSienkiewicz/.github/security/policy) describes.

A repository that has its own `CONTRIBUTING.md` follows that file instead of this one. The repository's README
says how to build and test it.

## Rules a change must follow

- **One change per branch and pull request**, on a branch named `<type>/<description>`.
- **Conventional Commits** for commit messages and pull request titles (`feat`, `fix`, `docs`, `test`, `refactor`,
  `chore`).
- **No AI attribution** in commits, pull requests or titles.
- **A bug fix starts with a regression test** that fails without the fix. An existing test changes only when the
  contract it pins changes on purpose, and the pull request says why.
- **Documentation** that describes the changed behaviour changes in the same pull request.
- **No secrets** in the diff: no tokens, keys, `.env` files or credentials.

## Before you open a pull request

Run the formatter and the linter of what you touched, and the tests your change affects, as the repository's
README describes. A pull request that leaves the build red is not reviewed.

## Code of conduct

Everyone taking part follows the
[code of conduct](https://github.com/DominikSienkiewicz/.github/blob/HEAD/CODE_OF_CONDUCT.md).
