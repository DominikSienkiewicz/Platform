# roadmap toolkit — canonical logic (Platform) and per-repository config

One toolkit for "roadmap → GitHub Issues + Projects v2 + auto-unblock". **The logic is canonical in
Platform** (a single source of truth); a consumer repository keeps **one** file of values,
`scripts/lib/roadmap-config.sh`. Every repository uses the same `roadmap.md` format, so the parser is
shared.

## Files (canon → target in the consumer)

| Canonical file (`templates/roadmap/`) | Target in the consumer | Role |
|---|---|---|
| `scripts/roadmap-to-issues.sh` | `scripts/roadmap-to-issues.sh` | idempotent projection of the roadmap onto Issues and Projects v2 (key: the `roadmap-id:` marker) |
| `scripts/roadmap-unblock.sh` | `scripts/roadmap-unblock.sh` | unblocks dependents when a prerequisite closes; **the `--closed <N>` contract** (called by the reusable workflow) |
| `scripts/roadmap-project-setup.sh` | `scripts/roadmap-project-setup.sh` | one-time bootstrap of the board fields (Status, Stream, Roadmap ID) |
| `scripts/lib/roadmap-parse.sh` | `scripts/lib/roadmap-parse.sh` | parser of `roadmap.md` into TSV, plus the marker helpers (canon) |
| `scripts/lib/roadmap-lib.sh` | `scripts/lib/roadmap-lib.sh` | label and status helpers over the values from the config (canon) |
| `scripts/lib/roadmap-config.sh.example` | `scripts/lib/roadmap-config.sh` | **the only per-repository file**: values (title, paths, colour palettes); not re-synced |
| `scripts/lib/roadmap-parse.test.sh`, `roadmap-libs.test.sh` | `scripts/lib/…` | tests (a fixture and a static sanity check) |
| `scripts/lib/fixtures/roadmap.sample.md` | `scripts/lib/fixtures/…` | fixture for the hermetic parser test |
| `examples/roadmap-config.{bookofstyling,skillsprintplus}.sh` | — | ready per-repository values (rollout reference) |

Every script sources, in this order: `roadmap-config.sh` → `roadmap-lib.sh` → `roadmap-parse.sh`.

## Rolling it out to a repository (BookOfStyling, SkillSprintPlus and the next ones)

1. Copy `templates/roadmap/scripts/**` to the repository's `scripts/**` (it overwrites the old,
   drifted scripts).
2. Create `scripts/lib/roadmap-config.sh` from `roadmap-config.sh.example` (BookOfStyling and
   SkillSprintPlus: use the ready file from `examples/`).
3. Keep the thin caller `.github/workflows/roadmap-unblock.yml` with an explicit secret instead of
   `inherit`: `uses: …/Platform/…@vX.Y.Z` plus
   `secrets: { ROADMAP_PROJECT_TOKEN: ${{ secrets.ROADMAP_PROJECT_TOKEN }} }`
   (a classic PAT with `project` and `repo`, valid for 90 days at most). The `--closed` contract does
   not change.
4. **Marker self-heal** (safe): run `./scripts/roadmap-to-issues.sh --dry-run` (preview), then without
   `--dry-run`. The lookup by the stable `roadmap-id:` finds the existing Issue and **updates** it
   instead of creating a duplicate, and rewrites the marker into the canonical layout on the way. It
   needs the `ROADMAP_PROJECT_TOKEN` PAT (scope `project`).

## Notes

- Idempotency rests on the `roadmap-id:` marker: do not change its format without a migration.
- The scripts change GitHub (Issues, Projects v2). Always run `--dry-run` first.
- `GH_REPO` and `GH_OWNER` come from the environment or autodetection; `ROADMAP_PROJECT_NUMBER` comes
  from the repository variable or `--project` (deliberately outside the config).
