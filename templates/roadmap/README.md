# roadmap toolkit — canonical logic (Platform) and per-repository config

> **Experimental** (Decision 11). The toolkit is part of Platform and its fixes ship with Platform
> releases, but only the marker contract below is stable. The scripts, the TSV columns and the body
> layout may change in any release; adopters re-copy `scripts/**` after a bump.

One toolkit for "roadmap → GitHub Issues + Projects v2 + auto-unblock". **The logic is canonical in
Platform** (a single source of truth); a consumer repository keeps **one** file of values,
`scripts/lib/roadmap-config.sh`. Every repository uses the same `roadmap.md` format, so the parser is
shared.

## Files (canon → target in the consumer)

| Canonical file (`templates/roadmap/`) | Target in the consumer | Role |
|---|---|---|
| `scripts/roadmap-to-issues.sh` | `scripts/roadmap-to-issues.sh` | idempotent projection of the roadmap onto Issues and Projects v2 (key: the `roadmap-id:` marker) |
| `scripts/roadmap-unblock.sh` | `scripts/roadmap-unblock.sh` | unblocks dependents when a prerequisite closes as completed; **the `--closed <N>` contract** (called by the reusable workflow) |
| `scripts/roadmap-project-setup.sh` | `scripts/roadmap-project-setup.sh` | one-time bootstrap of the board fields (Status, Stream, Roadmap ID) |
| `scripts/lib/roadmap-parse.sh` | `scripts/lib/roadmap-parse.sh` | parser of `roadmap.md` into TSV, plus the marker helpers (canon) |
| `scripts/lib/roadmap-lib.sh` | `scripts/lib/roadmap-lib.sh` | label helpers over the values from the config (canon) |
| `scripts/lib/roadmap-config.sh.example` | `scripts/lib/roadmap-config.sh` | **the only per-repository file**: values (title, paths, streams, colour palettes); not re-synced |
| `scripts/lib/*.test.sh` | `scripts/lib/…` | tests: the parser on a fixture and its contract, the static sourcing check, and the generator, project setup and unblock against a gh stub |
| `scripts/lib/fixtures/` | `scripts/lib/fixtures/…` | the parser fixture, the gh stub and the shared test setup |
| `.github/ISSUE_TEMPLATE/roadmap-item.yml` | `.github/ISSUE_TEMPLATE/roadmap-item.yml` | issue form for an item added by hand; it emits the canonical marker |
| `examples/roadmap-config.{bookofstyling,skillsprintplus}.sh` | — | ready per-repository values (rollout reference) |

Every script sources, in this order: `roadmap-config.sh` → `roadmap-lib.sh` → `roadmap-parse.sh`.
`ROADMAP_STREAMS` is per repository; A to E is the default in the example config, and the parser and
the board accept whatever the config lists.

## Marker contract

The last line of every roadmap issue body is the marker, the only data the automation reads:

```text
<!-- roadmap-id: <ID> | change-id: <slug> | stream: <stream or empty> | depends-on: <ID,ID or empty> | status: <board status> -->
```

- `roadmap-id` is `F-<n>` or `S-<n>`, unique in the repository. It is the idempotency key: the
  generator finds an issue by it, so a new layout needs a migration of every issue.
- `depends-on` lists the prerequisite IDs; empty means none.
- `status` is the board status at the last re-sync. Once an issue exists, its `status:*` label wins
  (see Status ownership).
- Field order is fixed in what the toolkit writes, but `roadmap-unblock.sh` reads the fields in any
  order and treats a missing `depends-on` or `status` as empty, so the older SkillSprintPlus layout
  (`roadmap-id | depends-on | change-id | stream`) still works.

What the scripts need: the generator writes all five fields; `roadmap-unblock.sh` needs `roadmap-id`
and reads `depends-on`; `roadmap-project-setup.sh` reads no marker.

Projected from `roadmap.md`: Outcome, Change ID, PRD refs, Prerequisites, Status, Unknowns, Blockers
and Risk of every item, and the suggested issue title, Ready for `/10x-plan` and Notes columns of the
`## Backlog Handoff` table. Not projected: Parallel with, Unlocks and anything else.

## Status ownership

`roadmap.md` is the source of truth for new items and for everything in the body. Once an issue
exists, its Status belongs to the automation and the board (Decision 12): a re-sync does not move an
issue back from `ready` (or a later status) to `backlog` or `blocked` while every dependency in its
marker is closed, because that is an auto-unblock the roadmap has not caught up with yet. Update
`roadmap.md` when you can; `./scripts/roadmap-to-issues.sh --force-status` projects the roadmap status
again regardless.

## Rolling it out to a repository (BookOfStyling, SkillSprintPlus and the next ones)

1. Copy `templates/roadmap/scripts/**` to the repository's `scripts/**` (it overwrites the old,
   drifted scripts), and `templates/roadmap/.github/ISSUE_TEMPLATE/roadmap-item.yml` in place of a local
   form.
2. Create `scripts/lib/roadmap-config.sh` from `roadmap-config.sh.example` (BookOfStyling and
   SkillSprintPlus: use the ready file from `examples/`).
3. Keep the thin caller `.github/workflows/roadmap-unblock.yml` with an explicit secret instead of
   `inherit`: `uses: …/Platform/…@vX.Y.Z` plus
   `secrets: { ROADMAP_PROJECT_TOKEN: ${{ secrets.ROADMAP_PROJECT_TOKEN }} }`
   (a classic PAT with `project` and `repo`, valid for 90 days at most). That secret is for Actions
   only; locally the scripts use your `gh auth` token, which needs `gh auth refresh -s project`.
   Set the repository variable `ROADMAP_PROJECT_NUMBER` to the board number.
4. **Marker self-heal.** It rewrites the title and the whole body of every existing issue, so check it
   on one item first: `./scripts/roadmap-to-issues.sh --preview <ID>`, then `--dry-run`, which lists
   the title changes. Run it without `--dry-run` only when the preview matches. The lookup by the stable
   `roadmap-id:` finds the existing issue and updates it instead of creating a duplicate, and rewrites
   the marker into the canonical layout.

## Verify the rollout

```bash
gh secret list | grep ROADMAP_PROJECT_TOKEN
```

```bash
gh variable get ROADMAP_PROJECT_NUMBER
```

```bash
./scripts/roadmap-unblock.sh --closed <number of a closed prerequisite> --dry-run
```

The last command must print `Closed prerequisite: #N (ID)` and list its dependents.

## Adoption status

As of 2026-10-19, from the GitHub API:

| Repository | Scripts synced | Markers | `ROADMAP_PROJECT_TOKEN` | `ROADMAP_PROJECT_NUMBER` | Unblock runs |
|---|---|---|---|---|---|
| BookOfStyling_com | 2026-07-06 (69c4472) | canonical | missing | missing | 0 |
| SkillSprintPlus_com | 2026-07-06 (27696f6) | older layout, self-heal not run | missing | missing | 0 |

Until the secret and the variable exist, the reusable workflow ends with a warning and changes nothing.

## Notes

- The scripts change GitHub (Issues, Projects v2). Always run `--dry-run` first.
- `GH_REPO` and `GH_OWNER` come from the environment or autodetection; `ROADMAP_PROJECT_NUMBER` comes
  from the repository variable or `--project` (deliberately outside the config).
- `ROADMAP_ISSUE_LIMIT` (default 5000) bounds the issue snapshot of the generator and the unblock; a
  snapshot that reaches it stops the run.
