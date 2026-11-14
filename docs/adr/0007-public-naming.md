# ADR-0007: Public naming of Platform artifacts and configuration keys

## Status

Accepted — 2026-10-18

## Context

A consumer meets Platform through names: the plugins it applies, the coordinates it resolves, the
properties it sets. Those names grew one release at a time and use four roots:

| Root | Names | Examples |
| --- | --- | --- |
| `seniordev.` | Gradle plugin IDs | `seniordev.java-conventions`, `seniordev.settings-conventions` |
| `pl.seniordeveloper` | Maven groups and Java packages | `pl.seniordeveloper.gradle:build-logic`, `pl.seniordeveloper:platform-catalog`, `pl.seniordeveloper.platform.security` |
| `@dominiksienkiewicz/` | npm scope | `@dominiksienkiewicz/versions`, `@dominiksienkiewicz/eslint-config` |
| `platform` | Spring properties, Gradle tasks, Gradle properties, npm bins | `platform.security.mode`, `platformDependencyCheck`, `platformVersion`, `platform-bump` |

Within the last root the Gradle properties disagree: `platformVersion` and `platformRepository` carry
the prefix, `coverageMinimum` and `sonarProjectKey` do not, and the registry credentials are
`gpr.user` and `gpr.key`. Only the npm scope had a recorded reason: GitHub Packages accepts an npm
package only under the scope of the repository owner, so the scope is the owner's name, not the
product's. Nothing told the author of the next knob which form to use, so to a reader the mix looks
accidental.

## Decision

- **Existing names are frozen.** Every name above is part of the public contract. Renaming one costs
  an edit in each of the five consumers and a consumer action in a MINOR release, for no gain in
  behaviour, so none is renamed. That includes `coverageMinimum`, `sonarProjectKey` and `gpr.*`.
- **The roots keep their roles.** A new plugin ID starts with `seniordev.`, a new Maven artifact goes
  in group `pl.seniordeveloper` (plugins in `pl.seniordeveloper.gradle`) with an artifact ID starting
  with `platform-`, and a new npm package goes in the `@dominiksienkiewicz/` scope. The npm scope
  follows the repository owner: moving the repository to another owner changes the scope and every
  consumer's `.npmrc` with it.
- **New keys carry the `platform` prefix:**
  - a Spring property goes under `platform.<area>.*`, kebab-case, as `platform.security.*` and
    `platform.cors.*` do;
  - a Gradle property is `platform.<area>.<name>`, with the name in lower camel case, such as
    `platform.coverage.minimum` would be;
  - a Gradle task is `platform<Name>`, like `platformBomOverrideCheck`;
  - an npm bin is `platform-<name>`, like `platform-versions-check`;
  - a reusable workflow input or secret is kebab-case or snake_case as its neighbours in the same
    workflow are; it needs no prefix, because the workflow already scopes it.
- An exception needs a reason written next to the name, for example a key whose name a third-party
  tool fixes.

## Consequences

- A consumer can tell a Platform knob from a Gradle, Spring or tool setting by its prefix, for every
  key added from now on.
- The existing Gradle properties keep their form, the camel-case `platformVersion` and
  `platformRepository` included; `docs/reference.md` lists them with the rest.
- A reviewer of a pull request that adds a public name checks it against this list.

## Revisit when

A MAJOR release is planned for another reason. Renaming the frozen keys then costs one more line
in an upgrade that consumers already have to make, and the old names can be kept as deprecated
aliases for one MAJOR.
