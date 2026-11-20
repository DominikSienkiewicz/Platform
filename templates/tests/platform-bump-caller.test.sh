#!/usr/bin/env bash
# Wzór callera cotygodniowego bumpu (templates/github/workflows/platform-bump.yml), który konsument kopiuje do
# .github/workflows/: poniedziałkowy cron i workflow_dispatch, kontrakt reusable platform-bump.yml ze snapshotu
# (platform-workflows-check bez błędów i ostrzeżeń), dokładny tag, który przesuwa blok workflows platform-bump,
# oraz sekrety, których szuka scripts/repo-settings.sh.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
template="$root/templates/github/workflows/platform-bump.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -s "$template" ]] || fail "missing ${template#"$root"/}"

# --- trigger ---
grep -qx '    - cron: "0 6 \* \* 1"' "$template" || fail 'the caller runs every Monday at 06:00 UTC'
grep -qx '  workflow_dispatch:' "$template" || fail 'the caller can be started by hand'

# --- pin ---
# Dokładny tag wydania (Decyzja 3), nie SHA: tylko taki ref przesuwa platform-bump i tylko taki akceptuje
# platform-workflows-check bez ostrzeżenia.
uses_re='^    uses: DominikSienkiewicz/Platform/\.github/workflows/platform-bump\.yml@v[0-9]+\.[0-9]+\.[0-9]+$'
[[ $(grep -cE "$uses_re" "$template") == 1 ]] || fail 'the caller calls platform-bump.yml by one exact vX.Y.Z tag'
tag=$(grep -E "$uses_re" "$template" | sed -E 's/.*@//')

# --- contract ---
repo="$tmp/repo"
mkdir -p "$repo/.github/workflows"
cp "$template" "$repo/.github/workflows/platform-bump.yml"
python3 "$root/frontend/packages/versions/bin/workflows-check.py" --ref "$tag" \
  --contract "$root/templates/tests/fixtures/workflow-contract.txt" --root "$repo" > "$tmp/check.txt" \
  || fail "the caller breaks the contract of platform-bump.yml: $(cat "$tmp/check.txt")"
[[ ! -s "$tmp/check.txt" ]] || fail "platform-workflows-check must report nothing: $(cat "$tmp/check.txt")"

# --- secrets ---
grep -qx '      gpr_token: ${{ secrets.GPR_TOKEN }}' "$template" || fail 'the caller passes GPR_TOKEN as gpr_token'
grep -qx '      bump_token: ${{ secrets.PLATFORM_BUMP_TOKEN }}' "$template" \
  || fail 'the caller passes PLATFORM_BUMP_TOKEN, the secret scripts/repo-settings.sh checks, as bump_token'
grep -q 'secrets/PLATFORM_BUMP_TOKEN' "$root/scripts/repo-settings.sh" || fail 'repo-settings.sh checks PLATFORM_BUMP_TOKEN'

# --- bump ---
# Blok workflows z bin/platform-bump.sh przesuwa ref skopiowanego callera do celu bumpu, więc wzór nie wymaga
# placeholdera: konsument ustawia swój pin, a każdy kolejny bump przesuwa go razem z innymi referencjami.
awk '
  index($0, "# platform-bump:workflows-end") { exit }
  inside { print }
  index($0, "# platform-bump:workflows") { inside = 1 }
' "$root/frontend/packages/versions/bin/platform-bump.sh" > "$tmp/workflows.sh"
[[ -s "$tmp/workflows.sh" ]] || fail 'no "# platform-bump:workflows" block in bin/platform-bump.sh'
(cd "$repo" && OWNER=DominikSienkiewicz TARGET=99.0.0 bash "$tmp/workflows.sh")
grep -qx '    uses: DominikSienkiewicz/Platform/.github/workflows/platform-bump.yml@v99.0.0' \
  "$repo/.github/workflows/platform-bump.yml" || fail 'platform-bump must move the caller to the bumped tag'

# --- docs ---
# docs/reusable-workflows.md pokazuje wzór przez docs-gen (`<!-- include: …#La-Lb -->`) bez polskiego nagłówka
# komentarzy: zakres musi zaczynać się od `name:` i kończyć na ostatnim wierszu, inaczej wycinek po cichu się utnie.
range=$(sed -nE 's|^<!-- include: templates/github/workflows/platform-bump\.yml#L([0-9]+)-L([0-9]+) -->$|\1 \2|p' \
  "$root/docs/reusable-workflows.md")
[[ -n "$range" ]] || fail 'docs/reusable-workflows.md must include the caller template'
read -r first last <<<"$range"
[[ "$first" == "$(grep -n '^name:' "$template" | cut -d: -f1)" ]] || fail 'the docs snippet must start at the name: line'
[[ "$last" == "$(wc -l < "$template" | tr -d ' ')" ]] || fail 'the docs snippet must end at the last line of the template'

echo "OK: the weekly platform-bump caller ($tag) runs on Monday and by hand, holds the contract and moves with every bump"
