# Platform

Platform is the shared build, quality, version and frontend layer of a set of product repositories: Gradle
convention plugins, a version catalog and BOM, test fixtures, incubating Spring Boot starters, npm packages,
reusable GitHub workflows and the templates every repository copies. One release pins all of it, and
`platform-bump` moves a consumer from one release to the next.

## Start here

- [Consuming Platform](consuming.md): prerequisites, the Gradle and frontend wiring, CI and troubleshooting.
- [Reference](reference.md): every task, property and default the plugins and starters add.
- [Reusable workflows](reusable-workflows.md): what each workflow does, its permissions and its inputs.
- [Gate codes](gates.md): what a `[PLAT-…]` failure means and how to fix it.
- [Versions](versions.md): where every version comes from and how the canon moves.

## For agents and maintainers

- [Rules for agents in consumer repositories](consumer-agents.md) and the [agent profile](agent-profile.md).
- [Runbooks](runbooks/README.md): adding a library, bumping a consumer, testing an unreleased change, releasing.
- [Architecture decisions](adr/README.md) and [engineering with agents](engineering-with-agents.md).
- [A reviewer's tour](tour.md) and the [incident notes](notes/).

This site is built from `docs/` of the repository with [Zensical](https://zensical.org); the source of truth stays
in the repository, so a page links to the code it describes on GitHub.
