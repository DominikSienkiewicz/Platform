# Runbook: rolling back a bad Platform release

Published versions are immutable: GitHub Packages refuses to publish a version twice, and a
consumer's lockfile and verification metadata record the checksums of what it downloaded. A bad
release is therefore fixed forward, and consumers are kept off it with the yank list.

## A release is broken

1. Add a line to [`releases/yanked.txt`](../../releases/yanked.txt) on `main`: the version, the
   reason and the replacement. From then on `platform-bump` without a version skips it, and an
   explicit `platform-bump <version>` refuses it unless `--allow-yanked` is passed.
2. Fix forward: merge the fix and cut the next release with `./release.sh` ([RELEASING.md](../../RELEASING.md)).
   A fix that only consumers need to take is a PATCH; one that needs consumer action is a MINOR
   with a **Consumer action required** entry ([ADR-0002](../adr/0002-release-and-versioning-contract.md)).
3. Say in the new release's CHANGELOG section which version it replaces and why.

Do not delete the bad version from GitHub Packages while a consumer still pins it: its builds
would stop resolving. `scripts/consumer-audit.sh` lists every consumer's pins.

## A consumer must go back

From the consumer's root, pin the previous good release explicitly:

```bash
./scripts/platform-bump.sh 1.5.30
```

The bump regenerates `gradle.lockfile`, `gradle/verification-metadata.xml` and
`package-lock.json` for that release: they record what the build downloaded, so the files of the
bad release would fail dependency verification or keep its versions. Review the diff with
`./scripts/platform-bump.sh --dry-run 1.5.30` first. If the bump fails half-way, it restores
every file it changed.

## A release was published only in part

`release.yml` stops on a failed Maven publication and names the module. A version that reached
only some registries cannot be published again: yank it, then cut the next version. The
`verify-published` job of the next release proves that every artifact carries it.

## The moving `v1` tag points at a bad release

`move-v1` in `release.yml` moves `v1` forward only. Callers on `@v1` take every release, so
point them at an exact tag with `platform-bump`, which rewrites `@v1` to the target. Moving `v1`
back by hand, by re-pointing the tag at the previous release and pushing it, is a last resort the
owner decides on, because it changes the code every `@v1` caller runs on its next job.

## An application deploy goes wrong

This runbook covers Platform artifacts only. Rolling back a deployed application is the deploy
workflow's concern: redeploy the previous image tag with `deploy.yml`.
