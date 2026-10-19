#!/usr/bin/env bash
# Kody bramek (N-SHOW-8) to publiczny kontrakt: każdy kod w źródłach (build-logic, biny paczki versions, workflowy)
# ma sekcję w docs/gates.md, a każda sekcja nazywa kod, który coś jeszcze emituje.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }

used=$(grep -rhoE 'PLAT-[A-Z]+-[0-9]{3}' "$root/gradle/build-logic/src" "$root/frontend/packages/versions/bin" "$root/.github/workflows" | sort -u)
documented=$(grep -oE '^### PLAT-[A-Z]+-[0-9]{3}$' "$root/docs/gates.md" | sed 's/^### //' | sort -u)
[[ -n "$used" ]] || fail 'no gate code found in the sources'
missing=$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$documented"))
unused=$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$documented"))
[[ -z "$missing" ]] || fail "codes without a section in docs/gates.md: $(tr '\n' ' ' <<<"$missing")"
[[ -z "$unused" ]] || fail "docs/gates.md documents codes nothing emits: $(tr '\n' ' ' <<<"$unused")"
[[ $(grep -cE '^### PLAT-' "$root/docs/gates.md") -eq $(wc -l <<<"$documented") ]] || fail 'a code has two sections in docs/gates.md'
echo "OK: $(wc -l <<<"$used" | tr -d ' ') gate codes, each with one section in docs/gates.md"
