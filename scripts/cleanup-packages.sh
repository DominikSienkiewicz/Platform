#!/usr/bin/env bash
# cleanup-packages.sh — ŚWIADOME sprzątanie starych wersji pakietów Platform w GitHub Packages.
#
# Zostawia N najnowszych wersji każdego pakietu (po created_at) i NIGDY nie rusza wersji z --protect,
# czyli pinów konsumentów — bez tej listy odmawia. Domyślnie wypisuje tylko plan; kasuje wyłącznie
# z --execute. Woła go .github/workflows/cleanup-packages.yml; zasady: RELEASING.md, "Package retention".
#
# Użycie:
#   scripts/cleanup-packages.sh --protect 1.5.26,1.5.31 [--keep 10] [--execute]
#
# Wymaga gh z GH_TOKEN (PAT classic: read:packages + delete:packages) oraz jq.
set -euo pipefail

KEEP=10
PROTECT=""
EXECUTE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) KEEP="${2:-}"; shift 2 ;;
    --protect) PROTECT="${2:-}"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done

[[ "$KEEP" =~ ^[0-9]+$ ]] || { echo "--keep must be a non-negative number, got '$KEEP'." >&2; exit 2; }
PROTECT="${PROTECT//[[:space:]]/}"
[[ -n "$PROTECT" ]] || {
  echo "--protect is required: list every Platform version a consumer still pins, comma-separated (e.g. 1.5.26,1.5.31)." >&2
  exit 1
}
[[ "$PROTECT" =~ ^[0-9]+\.[0-9]+\.[0-9]+(,[0-9]+\.[0-9]+\.[0-9]+)*$ ]] || {
  echo "--protect must be a comma-separated list of X.Y.Z versions, got '$PROTECT'." >&2
  exit 1
}

# Filtr bezpieczeństwa: tylko pakiety Platform, nigdy inne pakiety konta.
PLATFORM_RE='^(pl\.seniordeveloper|seniordev\.|@dominiksienkiewicz/)'
if [[ "$EXECUTE" == 1 ]]; then
  echo "Mode: execute — planned versions are deleted."
else
  echo "Mode: dry run — nothing is deleted; rerun with --execute to delete."
fi
echo "Keep the $KEEP newest versions of every package; never delete: $PROTECT"

planned=0
for type in maven npm; do
  packages=$(gh api --paginate "/user/packages?package_type=$type" --jq '.[].name' | grep -E "$PLATFORM_RE" || true)
  if [[ -z "$packages" ]]; then
    echo "$type: no Platform packages"
    continue
  fi
  while IFS= read -r package; do
    encoded=$(printf '%s' "$package" | jq -sRr @uri)
    plan=$(gh api --paginate "/user/packages/$type/$encoded/versions" --jq '.[]' \
      | jq -rs --argjson keep "$KEEP" --arg protect "$PROTECT" '
          ($protect | split(",")) as $protected
          | sort_by(.created_at) | reverse | .[$keep:]
          | map(select(.name as $name | $protected | index($name) | not))
          | .[] | "\(.id) \(.name)"')
    if [[ -z "$plan" ]]; then
      echo "  $type $package: nothing to delete"
      continue
    fi
    while read -r id version; do
      planned=$((planned + 1))
      if [[ "$EXECUTE" == 1 ]]; then
        echo "  $type $package: deleting $version (id=$id)"
        gh api --method DELETE "/user/packages/$type/$encoded/versions/$id" >/dev/null
      else
        echo "  $type $package: would delete $version (id=$id)"
      fi
    done <<< "$plan"
  done <<< "$packages"
done

if [[ "$EXECUTE" == 1 ]]; then
  echo "Done: $planned version(s) deleted."
else
  echo "Done: $planned version(s) would be deleted."
fi
