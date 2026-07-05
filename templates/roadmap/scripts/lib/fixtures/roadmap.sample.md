---
project: "Sample"
version: 1
status: draft
---

# Roadmap: Sample

> Small hermetic fixture for roadmap-parse.test.sh. 2 foundations + 3 slices.

## At a glance

| ID   | Change ID          | Outcome                          | Prerequisites | PRD refs | Status   |
| ---- | ------------------ | -------------------------------- | ------------- | -------- | -------- |
| F-01 | auth-gate          | (foundation) routes behind login | —             | FR-001   | ready    |
| F-02 | catalog-seed       | (foundation) catalog seeded      | —             | FR-006   | ready    |
| S-01 | populate-wardrobe  | populate wardrobe from catalog   | F-01, F-02    | US-01    | proposed |
| S-02 | wardrobe-roast     | generate a roast receipt         | S-01          | US-02    | ready     |
| S-03 | vinted-zip-import  | import wardrobe from a ZIP       | S-01, S-02    | FR-023   | blocked  |

## Streams

| Stream | Theme        | Chain                        | Note                    |
| ------ | ------------ | ---------------------------- | ----------------------- |
| A      | Anchor       | `F-01` → `S-01` → `S-02`     | Critical north-star path |
| B      | Sell-or-keep | `F-02` → `S-01`              | Feeds the anchor        |
| C      | AI extensions| `S-02`                       | Reuses the S-02 gateway |
| D      | Import       | `S-03`                       | Blocked track           |
| E      | Journal      | —                            | Independent             |

## Foundations

### F-01: Auth gate

- **Outcome:** all product routes are behind login; user can register, verify email, log in/out.
- **Change ID:** auth-gate
- **PRD refs:** FR-001
- **Prerequisites:** —
- **Parallel with:** F-02
- **Blockers:** —
- **Unknowns:** —
- **Status:** ready

### F-02: Catalog seed

- **Outcome:** a pre-seeded brand catalog is in the database and queryable.
- **Change ID:** catalog-seed
- **PRD refs:** FR-006
- **Prerequisites:** —
- **Parallel with:** F-01
- **Blockers:** —
- **Unknowns:** —
- **Status:** ready

## Slices

### S-01: Populate wardrobe from catalog

- **Outcome:** user fills the wardrobe by tapping items from the catalog and browses the grid.
- **Change ID:** populate-wardrobe
- **PRD refs:** US-01
- **Prerequisites:** F-01, F-02
- **Parallel with:** —
- **Blockers:** —
- **Unknowns:** —
- **Status:** proposed

### S-02: Wardrobe roast and receipt

- **Outcome:** user generates a roast of the wardrobe and downloads a shareable receipt.
- **Change ID:** wardrobe-roast
- **PRD refs:** US-02
- **Prerequisites:** S-01
- **Parallel with:** S-03
- **Blockers:** —
- **Unknowns:** —
- **Status:** ready

### S-03: Import wardrobe from a Vinted ZIP

- **Outcome:** user uploads a Vinted GDPR export (ZIP) and the system builds wardrobe items from it.
- **Change ID:** vinted-zip-import
- **PRD refs:** FR-023
- **Prerequisites:** S-01, S-04
- **Parallel with:** —
- **Blockers:** Legal opinion (P1) + data-path POC (P2) — is the Vinted export parser stable and legal for v1.
- **Unknowns:**
  - Parser depends on the Vinted export format and re-activates the image pipeline — is it stable enough for v1? (PRD Open Q7) — Owner: user. Block: yes.
  - Attribution/licensing of imported images is unresolved. Block: yes.
- **Status:** blocked

## Backlog Handoff

(end)
