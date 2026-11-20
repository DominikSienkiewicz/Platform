#!/usr/bin/env bash
# Blok open-pr z platform-bump.yml, przypadek po przypadku: gałąź, pull request i to, co może wypchnąć GITHUB_TOKEN, oraz
# raport wpływu nad logiem bumpa. Blok jest wycinany między znacznikami i uruchamiany w prawdziwym repozytorium, którego
# origin to lokalne bare repo, z atrapą gh.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

# --- open-pr ---
# The open-pr block of platform-bump.yml: it commits the applied bump to platform-bump/v<target>, pushes the
# branch and opens a pull request; it does nothing without a diff or when the branch exists, and without a
# bump_token it leaves workflow files alone, because GITHUB_TOKEN may not push them. The block is cut out
# between its markers and run in a real repository whose origin is a local bare repository, with a stub gh.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fail() { local message="$1"; echo "FAIL: $message" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

awk '
  index($0, "# >>> open-pr") { inside = 1; next }
  index($0, "# <<< open-pr") { inside = 0 }
  inside
' "$root/.github/workflows/platform-bump.yml" > "$tmp/open-pr.sh"
OUT=""
[[ -s "$tmp/open-pr.sh" ]] || fail 'platform-bump.yml has no open-pr block between its markers'

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CALLS"
previous=""
for arg in "$@"; do [[ "$previous" == --body-file ]] && cp "$arg" "$GH_BODY"; previous="$arg"; done
echo "https://github.com/owner/repo/pull/1"
GH
chmod +x "$tmp/bin/gh"
printf '==> Release notes from 1.5.31 to 1.6.0:\nCONSUMER ACTION REQUIRED\n' > "$tmp/bump.log"

# seed <name>: a repository with one workflow and a pin, pushed to its bare origin; prints its path.
seed() {
  local work="$tmp/$1"
  git init -q --bare -b main "$work.git"
  git init -q -b main "$work"
  mkdir -p "$work/.github/workflows" "$work/backend"
  printf 'uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.5.31\n' > "$work/.github/workflows/ci.yml"
  printf 'platformVersion=1.5.31\n' > "$work/backend/gradle.properties"
  git -C "$work" add -A
  git -C "$work" -c user.name=t -c user.email=t@example.invalid commit -q -m initial
  git -C "$work" remote add origin "$work.git"
  git -C "$work" push -q origin main
  printf '%s\n' "$work"
}

bump() {
  local work="$1"
  sed -i.bak 's/1\.5\.31/1.6.0/' "$work/backend/gradle.properties" "$work/.github/workflows/ci.yml"
  rm -f "$work/backend/gradle.properties.bak" "$work/.github/workflows/ci.yml.bak"
}

run() {
  local work="$1" token="$2"
  : > "$tmp/gh-calls"
  RC=0
  OUT=$(cd "$work" && PATH="$tmp/bin:$PATH" GH_CALLS="$tmp/gh-calls" GH_BODY="$tmp/gh-body" RUNNER_TEMP="$tmp" \
    TARGET="${TARGET-1.6.0}" BASE=main BUMP_LOG="$tmp/bump.log" BUMP_TOKEN="$token" PUSH_TOKEN="${token:-github-token}" \
    bash "$tmp/open-pr.sh" 2>&1) || RC=$?
}

# (a) a bump with a bump_token: branch pushed with every change, pull request opened against the base
work=$(seed with-token)
bump "$work"
run "$work" pat
[[ $RC -eq 0 ]] || fail "a bump must open a pull request (exit $RC)"
git -C "$work.git" rev-parse --verify -q refs/heads/platform-bump/v1.6.0 > /dev/null || fail 'the bump branch must be pushed'
git -C "$work.git" show platform-bump/v1.6.0:.github/workflows/ci.yml | grep -q '@v1.6.0' || fail 'with a bump_token the workflow refs move too'
grep -q '^pr create --base main --head platform-bump/v1.6.0 --title chore(platform): bump Platform to 1.6.0' "$tmp/gh-calls" \
  || fail "the pull request must target the base with the bump title: $(cat "$tmp/gh-calls")"
grep -q 'CONSUMER ACTION REQUIRED' "$tmp/gh-body" || fail 'the pull request body must carry the bump log'
if grep -q 'GITHUB_TOKEN' <<<"$OUT"; then fail 'no warning about GITHUB_TOKEN when a bump_token is set'; fi

# (b) the branch already exists: nothing is pushed or opened
run "$work" pat
[[ $RC -eq 0 ]] || fail "an existing bump branch is not an error (exit $RC)"
[[ ! -s "$tmp/gh-calls" ]] || fail 'no second pull request for an existing branch'

# (c) without a bump_token the workflow change is dropped, and the pull request says why
work=$(seed without-token)
bump "$work"
run "$work" ""
[[ $RC -eq 0 ]] || fail "a bump without a bump_token must still open a pull request (exit $RC)"
git -C "$work.git" show platform-bump/v1.6.0:.github/workflows/ci.yml | grep -q '@v1.5.31' || fail 'GITHUB_TOKEN may not push workflow changes'
git -C "$work.git" show platform-bump/v1.6.0:backend/gradle.properties | grep -qx 'platformVersion=1.6.0' || fail 'the pins must still be bumped'
grep -q 'were not moved' "$tmp/gh-body" || fail 'the pull request must say the workflow refs stayed'
grep -q '::warning::.*GITHUB_TOKEN' <<<"$OUT" || fail 'without a bump_token the run must warn that CI does not start'

# (d) nothing changed: no branch, no pull request
work=$(seed unchanged)
run "$work" pat
[[ $RC -eq 0 ]] || fail "an up-to-date repository is not an error (exit $RC)"
[[ ! -s "$tmp/gh-calls" ]] || fail 'no pull request without a diff'
if git -C "$work.git" rev-parse --verify -q refs/heads/platform-bump/v1.6.0 > /dev/null; then fail 'no branch without a diff'; fi

# (e) no target version: refuse
TARGET="" run "$work" pat
[[ $RC -ne 0 ]] || fail 'a run without a target version must fail'

echo 'OK: the bump pull request is opened once, carries the log, and respects what GITHUB_TOKEN may push'
)

# --- impact-report ---
# Blok open-pr z platform-bump.yml wkłada raport wpływu z `platform-bump --report` (N-REL-8) do treści pull requesta,
# gdy job bumpa go wytworzył, nad logiem; bez raportu treść jest taka jak dotąd.
(
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
OUT=""
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }
awk 'index($0, "# >>> open-pr") { inside = 1; next } index($0, "# <<< open-pr") { inside = 0 } inside' \
  "$root/.github/workflows/platform-bump.yml" > "$tmp/open-pr.sh"
grep -q 'BUMP_REPORT' "$tmp/open-pr.sh" || fail 'the open-pr block must read the report'
grep -q -- '--report=' "$root/.github/workflows/platform-bump.yml" || fail 'the bump job must ask platform-bump for the report'
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nprevious=""\nfor arg in "$@"; do [[ "$previous" == --body-file ]] && cp "$arg" "$GH_BODY"; previous="$arg"; done\n' > "$tmp/bin/gh"
chmod +x "$tmp/bin/gh"
printf 'bump log\n' > "$tmp/bump.log"
printf '## Platform 1.5.31 → 1.6.0: impact on this repository\n\n### Affects this repo\n\n- catalog `libs.jsoup`\n' > "$tmp/report.md"

# shellcheck disable=SC2329 # wołana niżej, w pętli przez nazwę
attempt() {
  local name=$1 report=$2 work="$tmp/$1"
  git init -q --bare -b main "$work.git"
  git init -q -b main "$work"
  mkdir -p "$work/backend"
  printf 'platformVersion=1.5.31\n' > "$work/backend/gradle.properties"
  git -C "$work" add -A
  git -C "$work" -c user.name=t -c user.email=t@example.invalid commit -q -m initial
  git -C "$work" remote add origin "$work.git"
  git -C "$work" push -q origin main
  printf 'platformVersion=1.6.0\n' > "$work/backend/gradle.properties"
  rm -f "$tmp/gh-body"
  OUT=$(cd "$work" && PATH="$tmp/bin:$PATH" GH_BODY="$tmp/gh-body" RUNNER_TEMP="$tmp" TARGET=1.6.0 BASE=main \
    BUMP_LOG="$tmp/bump.log" BUMP_REPORT="$report" BUMP_TOKEN=pat PUSH_TOKEN=pat bash "$tmp/open-pr.sh" 2>&1) || fail "$name: the block must succeed"
}

attempt with-report "$tmp/report.md"
grep -qF '### Affects this repo' "$tmp/gh-body" || fail 'the body must carry the impact report'
[[ $(grep -n 'Affects this repo' "$tmp/gh-body" | cut -d: -f1) -lt $(grep -n 'bump log' "$tmp/gh-body" | cut -d: -f1) ]] \
  || fail 'the report comes before the log'
attempt without-report "$tmp/absent.md"
grep -qF 'Affects this repo' "$tmp/gh-body" && fail 'without a report the body has none'
echo 'OK: the bump pull request carries the impact report above the bump log'
)
