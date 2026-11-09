# ADR-0036: Application images are signed keyless, and only after the scan gates

## Status

Accepted — 2026-11-09

## Context

A cluster that Argo CD keeps in sync ([ADR-0035](0035-promotion-by-commit-for-argo-cd.md)) should admit only images
that `deploy.yml` built and scanned. Kyverno `verifyImages` can enforce that, given a signature it can check. The
scan cannot enforce it alone, because `build-push` pushes each image before Grype scans it: an image that the gate
rejects is already in GHCR, and a hand-edited tag in the GitOps repository would deploy it.

GitHub artifact attestations (`actions/attest`, as `release.yml` uses them, [ADR-0017](0017-artifact-attestations-and-consumer-verification.md))
are not available to the consumers that promote. The signature is made in the calling repository, and in a private
repository GitHub offers attestations only on GitHub Enterprise Cloud. Azimuth and Training are private repositories
of a personal account.

## Decision

- With `scan-images: true`, `build-push` resolves each scanned tag to its digest once. Grype and Trivy scan that
  digest as two gates with the same threshold, `scan-severity`, and only findings that have a fix.
- A separate `sign` job signs exactly those digests with cosign keyless, through the public Sigstore instance. It
  needs `build-push`, so it signs nothing unless both gates passed. A signature therefore means that `deploy.yml`
  built the image for the named repository and both gates passed it.
- The public record is accepted. A key pair kept as a secret in every consumer would publish nothing, but its
  holder would be any workflow of that repository rather than `deploy.yml`, and the key would need storing and
  rotating. The owner chose keyless knowing what the logs keep.
- Only `sign` holds `id-token: write`. It checks nothing out and runs no code of the repository, so dependency code
  in the build never gets the signing identity. It refuses any reference that is not a digest of this application's
  backend or frontend image.
- Trivy runs in `build-push`, next to Grype, rather than in a job of its own. `build-push` already runs dependency
  code with `packages: write`, so a separate job would protect nothing that matters here. It would also change the
  condition of the `deploy` job.

## Consequences

- A caller of `deploy.yml` grants `id-token: write`. GitHub checks the permissions of every job in a called workflow
  before the run starts, so this applies even with `scan-images: false`. It is a contract change and a MINOR.
- Fulcio's certificate transparency log and Rekor record every signature, publicly and permanently, even for a
  private repository. They keep the calling repository and owner with their IDs and visibility, the calling
  workflow and its ref, the branch, the commit SHA, the trigger, the run URL with its ID, and Platform's workflow
  ref. The image's name, tag and content are not recorded, and no secret is. The names of the consumers are
  already public in `scripts/consumers.txt`. The full list is in
  [security-scanning.md](../security-scanning.md#signed-images).
- A finding accepted in `.grype.yaml` also needs an entry in `.trivyignore.yaml`, or Trivy fails the run.
- cosign 3 stores the signature as a Sigstore bundle, attached to the image as an OCI referrer, not as a
  `sha256-<digest>.sig` tag. The cluster's policy must use a verifier that reads such bundles, such as Kyverno's
  `ImageValidatingPolicy` from 1.19.2.
- The migration and `eval-worker` images are neither scanned nor signed. Only the SSH deploy uses them, and it
  verifies no signature.
- `promote.yml` pins `deploy.yml` at a release commit, so promotions are signed only after that pin moves to a
  release with this change. Its callers then grant `id-token: write` as well.

## Revisit when

The consumers become public, or move to a plan with artifact attestations in private repositories. A GitHub
attestation would then sign the same digests without a public Rekor entry for a private repository.
The record in the public logs becomes unacceptable for a consumer. Signing would then move to a key pair, or to
GitHub attestations once the plan allows them.
