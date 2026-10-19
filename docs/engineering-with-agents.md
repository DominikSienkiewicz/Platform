# Engineering with coding agents

Platform and its consumers are built with AI coding agents: the owner sets the architecture, writes the
specifications, defines the gates CI enforces and reviews every change. This page describes the operating
model behind that sentence, and where each rule is enforced rather than merely asked for.

## One task, one worktree, one branch

Every change starts in its own worktree under `.worktrees/`, on a branch named
`<type>/<description>-YYYY-MM-DD` cut from the latest `origin/main`
([`worktree-new.sh`](../templates/worktree-new.sh)). Agents never commit to `main`, `release` or a
`release/**` branch; the owner integrates with [`merge.sh`](../templates/merge.sh), which refuses on
uncommitted work, irreplaceable ignored files, a stale `origin/main`, a protected source or a second run in
parallel, and removes only the worktree and the branch it merged. [`worktree-status.sh`](../templates/worktree-status.sh)
shows which worktrees are ready. Rulesets keep `main` from being deleted or force-pushed and release tags
from moving ([RELEASING.md](../RELEASING.md#repository-settings)).

## A machine shared by many agents

Gradle, the JVM, Spring's test context cache and Vitest all size themselves for a machine they own, and
parallel agents multiply that. With `AI_AGENT=1`, the conventions and presets cap workers, forks, heaps and
cached contexts ([ADR-0010](adr/0010-agent-resource-profile.md)); [`agent-gradle.sh`](../templates/agent-gradle.sh)
lets only a few test runs proceed at once across separate Gradle invocations; and
[`agent-preflight.sh`](../templates/agent-preflight.sh) turns free memory and swap into go, reduce or stop
before agents are dispatched.

## Gates instead of instructions

An agent learns a rule fastest from a gate that fails with the fix:

- versions: `platformDependencyCheck` in Gradle and `platform-versions-check` in npm, each naming the alias
  or canon entry to use ([versions.md](versions.md));
- formatting and lint: Spotless, Checkstyle and ESLint run on every change, and a rule is fixed in the code,
  never weakened or suppressed without the owner's approval;
- contracts: the reusable workflow caller contract, the OpenAPI drift test and breaking-change gate
  ([api-contracts.md](api-contracts.md)), and the release contract in `release.sh`;
- diagnosis: `platform-doctor` names each broken precondition with an ID and a fix.

## Regression test first

Every bug fix starts with a test that reproduces the bug and would fail on the unfixed code, then the
smallest fix. An existing test is never weakened or deleted to make a build pass; when a contract really
changes, the owner approves the change to its test. The [incident notes](notes/) show the pattern: each
names the guard that now prevents the problem from coming back.

## Human review and a clean history

The owner reviews every change before it reaches `main`, and decisions with real trade-offs are put to the
owner with options and a recommendation, then recorded ([ADRs](adr/README.md)). Commits and pull requests
carry no AI attribution: the history describes the change, not the tool that typed it.
