## What and why

<!-- The goal of the change in a few sentences. Link the issue or ADR if it is architectural. -->

## Checklist
- [ ] `./gradlew check` (backend) and `npm run lint && npm test` (frontend) pass locally
- [ ] The README of every changed directory is updated
- [ ] Architectural decision → new ADR in `docs/adr/`
- [ ] A new Platform release is taken with `scripts/platform-bump.sh`, and the consumer actions in its notes are done
- [ ] No secrets, `.env` files or tokens in the diff
