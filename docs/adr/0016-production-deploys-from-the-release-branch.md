# ADR-0016: Production deploys run only from the release branch, with rollback by dispatch

## Status

Accepted — 2026-10-19

## Context

`deploy.yml` builds and deploys over SSH. Private repositories on the free plan cannot require reviewers on an
environment, so a reviewer gate was not available, and repository-level SSH secrets let any workflow on any branch
read the key.

## Decision

- The `deploy` job runs in the `production` environment, whose deployment branch policy admits only `release`, and
  the SSH secrets live in that environment (Decision 16). `templates/setup-gh-deploy.sh` sets it up.
- The host rolls an unhealthy layer back to the previous tag by itself; a dispatch with `rollback-to-backend` or
  `rollback-to-frontend` redeploys a tag that is already in GHCR without building (N-REL-12).

## Consequences

- A workflow on any other branch can neither deploy nor read the key.
- Database migrations are never rolled back, so schema changes must be expand/contract.

## Revisit when

The repositories move to a plan that offers required reviewers on private environments.
