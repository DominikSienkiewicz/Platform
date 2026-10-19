#!/usr/bin/env bash
# scripts/ci-budget.py na liście jobów z API: przekroczenie = ostrzeżenie, w budżecie = wiersz, brak budżetu = notka,
# pominięte joby poza tabelą; dopasowanie po najdłuższym prefiksie nazwy. Do tego: każdy job ci.yml ma budżet.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" "$tmp/summary" >&2 2>/dev/null; exit 1; }

cat > "$tmp/budgets.json" <<'JSON'
{ "CI": { "Frontend (Node ": 5, "Frontend (Node 22": 6, "Gradle — ": 8 } }
JSON
cat > "$tmp/jobs.json" <<'JSON'
{ "jobs": [
  { "name": "Gradle — build-logic", "conclusion": "success", "started_at": "2026-10-19T10:00:00Z", "completed_at": "2026-10-19T10:09:30Z" },
  { "name": "Frontend (Node 22.13.0) — install", "conclusion": "success", "started_at": "2026-10-19T10:00:00Z", "completed_at": "2026-10-19T10:05:30Z" },
  { "name": "Frontend (Node 24) — install", "conclusion": "success", "started_at": "2026-10-19T10:00:00Z", "completed_at": "2026-10-19T10:02:00Z" },
  { "name": "PR title — Conventional Commit", "conclusion": "skipped", "started_at": "2026-10-19T10:00:00Z", "completed_at": "2026-10-19T10:00:01Z" },
  { "name": "Unbudgeted", "conclusion": "success", "started_at": "2026-10-19T10:00:00Z", "completed_at": "2026-10-19T10:01:00Z" }
] }
JSON
: > "$tmp/summary"
GITHUB_STEP_SUMMARY="$tmp/summary" python3 "$root/scripts/ci-budget.py" "$tmp/jobs.json" "$tmp/budgets.json" CI > "$tmp/out"
grep -qxF '::warning title=CI budget::Gradle — build-logic took 9.5 min, budget 8 min' "$tmp/out" || fail 'an overrun must warn'
if grep -qF 'Frontend (Node 22.13.0)' "$tmp/out"; then fail 'the longest prefix (6 min) applies, so 5.5 min is within'; fi
grep -qxF '| Frontend (Node 24) — install | 2.0 | 5 | within |' "$tmp/summary" || fail 'a job within budget gets a row'
grep -qxF '::notice title=CI budget::Unbudgeted has no budget in .github/ci-budgets.json' "$tmp/out" || fail 'a job without a budget is named'
if grep -qF 'PR title' "$tmp/summary"; then fail 'skipped jobs are left out'; fi

# Każdy job ci.yml (nazwa albo id joba wołającego reusable workflow) ma budżet.
python3 - "$root/.github/workflows/ci.yml" "$root/.github/ci-budgets.json" <<'PY'
import json, re, sys
budgets = json.load(open(sys.argv[2]))["CI"]
names, job, in_jobs = [], None, False
for line in open(sys.argv[1], encoding="utf-8"):
    if re.match(r"^\S", line):
        in_jobs = line.startswith("jobs:")
        continue
    head = re.match(r"^  ([a-z][a-z0-9-]*):\s*$", line) if in_jobs else None
    if head:
        job = head.group(1)
        names.append(f"{job} / ")
    name = re.match(r"^    name:\s*(.+?)\s*$", line)
    if name and job:
        names[-1] = re.sub(r"\$\{\{[^}]*\}\}", "24", name.group(1))
missing = [n for n in names if not any(n.startswith(prefix) for prefix in budgets)]
if missing:
    sys.exit("jobs of ci.yml without a budget in .github/ci-budgets.json: " + ", ".join(missing))
PY

echo 'OK: ci-budget warns on overruns, matches the longest prefix and covers every ci.yml job'
