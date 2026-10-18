## What and why

<!-- The goal of the change in a few sentences. Link the issue or ADR if it is architectural. -->

## Consumer impact

<!-- Every product repository that consumes the platform is affected by what lands here. Tick one. -->

- [ ] **None**: CI, docs or tests only; nothing published changes.
- [ ] **On bump**: changes a published artifact; consumers get it when they bump the platform pin.
- [ ] **Immediate**: changes a reusable workflow, which consumers call via `@v1`; it reaches them on
      their next CI run, without a bump.

### Consumer action required

<!--
Anything a consumer must do beyond bumping the pin: a new or renamed property, task or input, a
removed dependency, a new required secret, a stricter gate. Ships as a minor version in the 1.x line.
Write "None" if nothing is required.
-->

None.

## Checklist

- [ ] CI is green: every Gradle module, the frontend workspace and `templates/tests/*.test.sh`
- [ ] A new library or version is declared in `gradle/catalog/libs.versions.toml` or
      `frontend/packages/versions/versions.json` first
- [ ] `CHANGELOG.md` `[Unreleased]` entry for every published change, consumer action included
- [ ] README, `RELEASING.md` or `docs/` updated when published artifacts, workflows or consumer
      behaviour change
- [ ] Architectural decision → new ADR in `docs/adr/`
- [ ] No secrets, `.env` files or tokens in the diff
