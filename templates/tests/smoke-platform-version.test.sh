#!/usr/bin/env bash
# backend-ci-smoke w ci.yml buduje starter java-library z GitHub Packages. Commit wydania z release.sh podbija pin
# do wersji, którą release.yml publikuje dopiero po zielonym ci.yml (push main i tag niosą ten sam commit), więc
# smoke bierze wtedy pin rodzica, czyli ostatnie wydanie. Wersji, której nie ma w rejestrze (wydanie 1.7.0 nic nie
# opublikowało), smoke nie bierze: schodzi do najnowszej opublikowanej niższej. Blok wycięty spomiędzy markerów
# biegnie pod `bash -e` runnera na zasianym repo git, z atrapą `gh` zamiast rejestru.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
workflow="$root/.github/workflows/ci.yml"
OUT=""

fail() { local message="$1"; echo "FAIL: $message" >&2; echo "--- output ---" >&2; echo "$OUT" >&2; exit 1; }

awk '
  index($0, "# >>> smoke-platform-version") { inside = 1; next }
  index($0, "# <<< smoke-platform-version") { inside = 0 }
  inside
' "$workflow" > "$tmp/resolve.sh"
[[ -s "$tmp/resolve.sh" ]] || fail 'ci.yml has no smoke-platform-version block between its markers'
# shellcheck disable=SC2016 # wyrażenie GitHub Actions szukane dosłownie
grep -qF -- '-PplatformVersion=${{ needs.smoke-platform-version.outputs.version }}' "$workflow" \
  || fail 'backend-ci-smoke must build on the version the smoke-platform-version job resolves'

repo="$tmp/repo"
pin_file=templates/jvm/java-library/gradle.properties
git init -q -b main "$repo"
git -C "$repo" config user.name 'Smoke Test'
git -C "$repo" config user.email 'smoke-test@example.invalid'
mkdir -p "$repo/$(dirname "$pin_file")" "$repo/gradle"
printf '%s\n' '# moduł pakiet' 'build-logic seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin' \
  'catalog pl.seniordeveloper.platform-catalog' > "$repo/gradle/maven-modules.txt"

# Atrapa rejestru: `gh api` zwraca wersje markera settings-conventions z $tmp/published, GH_FAIL udaje błąd API.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
[[ -z "${GH_FAIL:-}" ]] || { echo 'HTTP 401: Bad credentials' >&2; exit 1; }
[[ "$*" == "api --paginate /users/DominikSienkiewicz/packages/maven/seniordev.settings-conventions.seniordev.settings-conventions.gradle.plugin/versions --jq .[].name" ]] \
  || { echo "unexpected gh $*" >&2; exit 2; }
cat "$PUBLISHED"
STUB
chmod +x "$tmp/bin/gh"
printf '%s\n' 1.6.0 1.5.31 1.5.30 v1 > "$tmp/published"

commit() {
  local pin="$1" message="$2"
  printf 'platformVersion=%s\n' "$pin" > "$repo/$pin_file"
  git -C "$repo" add -A
  git -C "$repo" commit -q --allow-empty -m "$message"
}

resolve() {
  : > "$tmp/output"
  RC=0
  OUT=$(cd "$repo" && PATH="$tmp/bin:$PATH" GH_LOG="$tmp/gh.log" PUBLISHED="$tmp/published" GPR_OWNER=DominikSienkiewicz \
    GITHUB_OUTPUT="$tmp/output" bash -e "$tmp/resolve.sh" 2>&1) || RC=$?
  RESOLVED=$(sed -n 's/^version=//p' "$tmp/output")
}

commit 1.5.31 'feat: the first commit'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.5.31 ]] || fail "a commit without a parent must build on its pin, got '$RESOLVED' (exit $RC)"

commit 1.6.0 'chore(release): platform 1.6.0'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.5.31 ]] \
  || fail "the release commit (push to main and the tag) must build on the published parent pin, got '$RESOLVED' (exit $RC)"
grep -qF 'builds on 1.5.31' <<<"$OUT" || fail 'the release commit must say why the smoke does not build on its own pin'

echo 'after the release' > "$repo/README.md"
commit 1.6.0 'docs: a commit after the release'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.6.0 ]] || fail "a commit after the release must build on its own pin, got '$RESOLVED' (exit $RC)"

commit 1.7.0 'chore(release): platform 1.7.0'
echo 'after the failed release' > "$repo/README.md"
commit 1.7.0 'fix: a commit after a release that published nothing'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.6.0 ]] \
  || fail "a pin missing from the registry (1.7.0 published nothing) must fall back to the newest published version below it, got '$RESOLVED' (exit $RC)"
grep -qF '1.7.0 is not in GitHub Packages, so the smoke builds on 1.6.0' <<<"$OUT" || fail 'the fallback must be announced with both versions'

commit 1.8.0 'chore(release): platform 1.8.0'
resolve
[[ $RC -eq 0 && "$RESOLVED" == 1.6.0 ]] \
  || fail "a release commit whose parent pin was never published must build on the newest published version, got '$RESOLVED' (exit $RC)"

GH_FAIL=1 resolve
[[ $RC -ne 0 ]] || fail 'an error of the registry API must fail the job, not pick a version blindly'
unset GH_FAIL

printf '%s\n' 1.9.0 > "$tmp/published"
echo 'nothing below' > "$repo/README.md"
commit 1.8.0 'docs: no published version below the pin'
resolve
[[ $RC -ne 0 ]] || fail 'without a published version at or below the pin the job must fail'
grep -qF '::error' <<<"$OUT" || fail 'the missing published version must be reported as an error'

echo 'OK: backend-ci-smoke builds a release commit on the previous release, every other commit on its pin, and an unpublished version on the newest published one below it'
