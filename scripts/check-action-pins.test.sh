#!/usr/bin/env bash
# check-action-pins.sh na atrapie `gh`, która rozwija tagi z tabeli zamiast z GitHuba. Przypadek z runu Scorecard
# z 2026-10-19: ossf/scorecard-action przypięty po SHA obiektu annotated taga v2.4.3 (99c09fe…), a nie po commicie
# 4eaacf0…, na który ten tag wskazuje — runner to uruchamia, ale publikacja wyniku pada na „imposter commit”.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$work/out.txt" >&2; exit 1; }

tag_object=99c09fe975337306107572b4fdf4db224cf8e2f2
scorecard_commit=4eaacf0543bb3f2c246792bd56e8cdeffafb205a
checkout_commit=d23441a48e516b6c34aea4fa41551a30e30af803
codeql_commit=6f2ac81f5cd81fe351a197ba0b00d91d03cd2aee

# Atrapa: `gh api repos/<owner>/<repo>/commits/<ref> --jq .sha` wypisuje SHA z $GH_REFS (wiersze "repo ref sha").
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
path="$2"
repo=$(cut -d/ -f2-3 <<<"$path")
ref=${path##*/}
sha=$(awk -v repo="$repo" -v ref="$ref" '$1 == repo && $2 == ref { print $3 }' "$GH_REFS")
[[ -n "$sha" ]] || { echo "gh: No commit found for SHA: $ref (HTTP 422)" >&2; exit 1; }
echo "$sha"
STUB
chmod +x "$work/bin/gh"
cat > "$work/refs.txt" <<REFS
actions/checkout v6.1.0 $checkout_commit
github/codeql-action v4.39.0 $codeql_commit
ossf/scorecard-action v2.4.3 $scorecard_commit
REFS

# repo <name> <workflow>: repozytorium git z jednym śledzonym workflowem.
repo() {
  mkdir -p "$work/$1/.github/workflows"
  printf '%s\n' "$2" > "$work/$1/.github/workflows/scan.yml"
  git -C "$work/$1" init -q
  git -C "$work/$1" add .github
}
run() { PATH="$work/bin:$PATH" GH_REFS="$work/refs.txt" bash "$here/check-action-pins.sh" "$work/$1" > "$work/out.txt" 2>&1; }

repo good "jobs:
  scan:
    steps:
      - uses: actions/checkout@$checkout_commit # v6.1.0
      - uses: ./.github/actions/local
      - uses: github/codeql-action/upload-sarif@$codeql_commit # v4.39.0
      - uses: ossf/scorecard-action@$scorecard_commit # v2.4.3"
run good || fail 'pins on the commits of their tags must pass, including an action in a subdirectory'
grep -qF 'OK: 3 action pins' "$work/out.txt" || fail 'the summary must count the three pins'

repo tag-object "jobs:
  scan:
    steps:
      - uses: actions/checkout@$checkout_commit # v6.1.0
      - uses: ossf/scorecard-action@$tag_object # v2.4.3"
if run tag-object; then fail 'a pin on the annotated tag object must fail'; fi
grep -qF ".github/workflows/scan.yml:5: ossf/scorecard-action@$tag_object is not the commit v2.4.3 points at" "$work/out.txt" \
  || fail 'the failure must name the file, the line and the pin'
grep -qF "Pin ossf/scorecard-action@$scorecard_commit # v2.4.3" "$work/out.txt" \
  || fail 'the failure must name the commit to pin'

repo no-comment "      - uses: actions/checkout@$checkout_commit"
if run no-comment; then fail 'a pin without a # vX.Y.Z comment must fail'; fi
grep -qF "has no '# vX.Y.Z' comment" "$work/out.txt" || fail 'the failure must ask for the version comment'

repo unknown-tag "      - uses: actions/checkout@$checkout_commit # v9.9.9"
if run unknown-tag; then fail 'a comment naming a tag the action does not have must fail'; fi
grep -qF 'tag v9.9.9 not found in actions/checkout' "$work/out.txt" || fail 'the failure must name the missing tag'

echo 'OK: check-action-pins.sh accepts pins on tag commits and rejects tag objects, missing comments and unknown tags'
