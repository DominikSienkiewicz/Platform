# ADR-0035: Promotion by commit replaces SSH deploy for a cluster managed by Argo CD

## Status

Accepted — 2026-11-05

## Context

`deploy.yml` builds and pushes images, then deploys them to one host over SSH
([ADR-0016](0016-production-deploys-from-the-release-branch.md)). A cluster that Argo CD keeps in sync with a Git
repository has no host to deploy to: the desired state is a commit, and a workflow that reaches into the cluster
would bypass the one place that records what runs. The consumers that still deploy over SSH must not change.

## Decision

- A consumer that targets such a cluster stops deploying over SSH and promotes instead: its release builds
  and scans the images, then commits the new image tags to the GitOps repository. Argo CD deploys the commit.
  Rolling back is reverting that commit.
- `promote.yml` is a reusable workflow that does both. Its `build` job calls `deploy.yml` with
  `ssh-deploy: false`, so building, scanning and pushing stay in one place and the SSH path is untouched:
  the input defaults to `true`, and with it nothing changes for existing callers. Its `promote` job writes the
  tags with `scripts/promote-image.sh`, taken from Platform at `platform-ref`.
- The commit is pushed with a GitHub App token that is limited to the GitOps repository and carries only
  `contents: write`, minted per run and revoked after it. The workflow passes its secrets explicitly and has no
  `concurrency` of its own, because the group of `deploy.yml` already serializes builds per application.

## Consequences

- The release workflow of a consumer no longer needs SSH secrets, `DEPLOY_PATH` or the `production` environment;
  it needs the App key as a repository secret, since environment secrets do not reach a reusable workflow
  without `secrets: inherit`. The key writes to the GitOps repository, and so indirectly to the cluster, which
  is why the caller must run it only from the release branch.
- There is no smoke test after the promotion: the runner cannot reach the cluster. Alerts and a manual check
  take its place.
- The build runs in a nested reusable workflow, called by its full reference at a commit. Version 1.8.9 used `./`,
  and its first real runs failed at startup with "workflow was not found": when a caller pins an annotated tag,
  GitHub looks a relative reference up at the tag object instead of its commit
  ([reported bug, no date for a fix](https://github.com/orgs/community/discussions/206746)). Platform's tags are
  annotated because they carry the changelog ([ADR-0002](0002-release-and-versioning-contract.md)).
- A change to `deploy.yml` reaches `promote.yml` only when that pin moves, in a later release; `RELEASING.md` has the
  step.
- Nothing is committed when the build fails. The App token and the push run in the own job of `promote.yml`, not in
  the nested call.

## Revisit when

The build moves out of `deploy.yml` into a workflow of its own that both `deploy.yml` and `promote.yml` call.
That is future work: it would change the SSH path, which has no tests that execute it, and would require
rewriting the tests that pin `deploy.yml`. Until then `promote.yml` wraps `deploy.yml`.

GitHub resolves a relative reference at the commit of an annotated tag. `promote.yml` can then return to `./`, and the
pin goes.
