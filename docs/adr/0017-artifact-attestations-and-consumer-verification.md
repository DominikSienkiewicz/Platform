# ADR-0017: Artifacts carry GitHub attestations, and consumers can verify them

## Status

Accepted — 2026-10-19

## Context

Consumers resolve Platform from GitHub Packages with a token. Without provenance, a compromised token or a
mistaken manual publish could put bytes into the registry that no workflow built.

## Decision

- `release.yml` attests every file it publishes with `actions/attest` (Decision 25): the jars, the catalog TOML,
  the npm tarballs and the release assets.
- `platform-bump` verifies the attestation of the package it runs (from 1.6.0 on), `backend-ci.yml` verifies every
  Platform jar with `verify-provenance: true` (PLAT-PROV-001), and `reproducibility.yml` rebuilds the latest tag
  every week and compares the digests with the registry (N-REL-16).

## Consequences

- A consumer can tell a Platform artifact from any other file with `gh attestation verify`.
- Reproducible archives are part of the contract: a release that does not rebuild to its published jars opens an
  issue.

## Revisit when

GitHub Packages offers signature verification of its own.
