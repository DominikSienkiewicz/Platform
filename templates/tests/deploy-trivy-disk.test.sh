#!/usr/bin/env bash
# Miejsce na bazy Trivy w deploy.yml: build-push buduje i wypycha obrazy, a Grype pobiera swoją bazę, zanim Trivy
# pobierze bazę Java DB (blisko 1 GB spakowana). Release Azimuth 0.1.69 padł na "no space left on device" przy jej
# pobieraniu, więc przed instalacją Trivy krok zwalnia cache buildx i bazę Grype, a na runnerze GitHuba także
# narzędzia obrazu, których job nie używa. Blok jest wycinany między znacznikami i uruchamiany z atrapami docker,
# sudo i df; na runnerze self-hosted nie dotyka niczego poza cache joba.
# shellcheck disable=SC2016 # literal GitHub expressions
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
workflow="$root/.github/workflows/deploy.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" 2>/dev/null >&2 || true; exit 1; }
block() {
  awk -v from="# >>> $1" -v to="# <<< $1" \
    'index($0, from) { inside = 1; next } index($0, to) { inside = 0 } inside { sub(/^          /, ""); print }' "$workflow"
}
job() { awk -v start="  $1:" '$0 == start { p = 1; next } /^  [a-z-]+:$/ { p = 0 } p' "$workflow"; }
step() { awk -v name="      - name: $2" 'index($0, name) == 1 { p = 1; print; next } p && /^      - / { p = 0 } p' <<< "$(job "$1")"; }
line_of() { grep -nF -- "$2" <<< "$(job "$1")" | head -1 | cut -d: -f1; }

toolchains=(/usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL)

# --- krok: po bramkach Grype, przed instalacją Trivy, tylko gdy obrazy są skanowane ---
disk_step=$(step build-push 'Free the disk for the Trivy databases')
[[ -n "$disk_step" ]] || fail "build-push must have the step 'Free the disk for the Trivy databases'"
grep -qFx '        if: ${{ inputs.scan-images }}' <<< "$disk_step" || fail 'the disk is freed exactly when the images are scanned'
grep -qF 'continue-on-error' <<< "$disk_step" && fail 'a failure to free the disk must show, not be hidden by continue-on-error'
disk_line=$(line_of build-push '- name: Free the disk for the Trivy databases')
grype_line=$(line_of build-push '- name: Grype scan — frontend (gate)')
trivy_line=$(line_of build-push '- name: Set up Trivy')
[[ "$grype_line" -lt "$disk_line" && "$disk_line" -lt "$trivy_line" ]] \
  || fail 'the disk is freed after the last Grype gate, which needs its database, and before Trivy is set up'

block trivy-disk > "$tmp/disk.sh"
[[ -s "$tmp/disk.sh" ]] || fail 'deploy.yml has no trivy-disk block between its markers'

mkdir -p "$tmp/bin"
for tool in docker sudo df; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" %s "$*" >> "$CALLS"\n[[ "%s" == docker && -n "${DOCKER_FAILS:-}" ]] && exit 1\nexit 0\n' \
    "$tool" "$tool" > "$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done
free_disk() {
  rm -rf "${tmp:?}/home"
  mkdir -p "$tmp/home/.cache/grype/db/6" "$tmp/home/.cache/trivy" "$tmp/home/.gradle/caches"
  : > "$tmp/calls"
  (env PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" HOME="$tmp/home" "$@" bash "$tmp/disk.sh") > "$tmp/out" 2>&1
}
calls_of() { grep "^$1 " "$tmp/calls" | cut -d' ' -f2- || true; }

# --- runner GitHuba: cache buildx, baza Grype i nieużywane narzędzia obrazu ---
free_disk RUNNER_ENVIRONMENT=github-hosted || fail 'the trivy-disk block must pass on a GitHub-hosted runner'
[[ "$(calls_of docker)" == 'buildx prune --all --force' ]] \
  || fail "the build cache of buildx must be pruned in full, got: $(calls_of docker | paste -sd'|' -)"
[[ ! -e "$tmp/home/.cache/grype" ]] || fail "Grype's database must be removed once the Grype gates have passed"
[[ -d "$tmp/home/.cache/trivy" && -d "$tmp/home/.gradle/caches" ]] || fail 'only the Grype cache is removed from the home directory'
[[ "$(calls_of sudo)" == "rm -rf ${toolchains[*]}" ]] \
  || fail "the unused toolchains of the runner image must be removed in one sudo rm -rf, got: $(calls_of sudo | paste -sd'|' -)"
[[ "$(calls_of df | paste -sd'|' -)" == '-h /|-h /' ]] || fail 'the free space must be logged before and after'
[[ "$(head -1 "$tmp/calls")" == 'df -h /' && "$(tail -1 "$tmp/calls")" == 'df -h /' ]] \
  || fail "the free space must be logged first and last, got: $(paste -sd'|' - < "$tmp/calls")"

# --- runner self-hosted: tylko cache joba, nic z systemu ---
free_disk RUNNER_ENVIRONMENT=self-hosted || fail 'the trivy-disk block must pass on a self-hosted runner'
[[ -z "$(calls_of sudo)" ]] || fail 'a self-hosted runner is not ours to strip: sudo must never run there'
[[ "$(calls_of docker)" == 'buildx prune --all --force' && ! -e "$tmp/home/.cache/grype" ]] \
  || fail 'a self-hosted runner still frees the buildx cache and the Grype database'
free_disk || fail 'the trivy-disk block must pass without RUNNER_ENVIRONMENT'
[[ -z "$(calls_of sudo)" ]] || fail 'without RUNNER_ENVIRONMENT the runner is not known to be GitHub-hosted, so sudo must not run'

# --- porażka prune nie zatrzymuje wydania, ale jest widoczna ---
free_disk RUNNER_ENVIRONMENT=github-hosted DOCKER_FAILS=1 || fail 'a failed buildx prune must not fail the release before Trivy runs'
grep -qF '::warning::' "$tmp/out" || fail 'a failed buildx prune must leave a warning in the log'
[[ -n "$(calls_of sudo)" && ! -e "$tmp/home/.cache/grype" ]] || fail 'a failed buildx prune must not stop the rest of the cleanup'

echo 'OK: deploy.yml frees the buildx cache, the Grype database and, on GitHub runners, unused toolchains before Trivy'
