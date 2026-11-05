#!/usr/bin/env bash
# Test promote-image.sh na prawdziwym git i lokalnym repo bare: zmiana wyłącznie image.tag, odmowa złych argumentów
# bez śladu w repo, jeden commit na wiele plików oraz wyścig z obcym commitem rozwiązany rebase'em i ponowieniem.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/promote-image.sh"
tmp=$(mktemp -d)
trap 'rm -r -f "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export GIT_AUTHOR_NAME=seed GIT_AUTHOR_EMAIL=seed@example.test GIT_COMMITTER_NAME=seed GIT_COMMITTER_EMAIL=seed@example.test
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

values_fixture() {
  cat <<'YAML'
# Azimuth backend values
replicaCount: 2
tag: top-level-stray
image:
  repository: ghcr.io/example/backend # keep me
  tag: 1.0.0 # pinned by promotion
  pullPolicy: IfNotPresent
sidecar:
  # not the application image
  tag: 9.9.9
YAML
}

# new_repos: bare + kopia robocza + druga kopia "other" do obcych commitów; ustawia $bare, $work, $other.
new_repos() {
  local n=$1
  bare="$tmp/$n/bare.git"; work="$tmp/$n/work"; other="$tmp/$n/other"
  mkdir -p "$tmp/$n"
  git init -q --bare -b main "$bare"
  git clone -q "$bare" "$work" 2> /dev/null
  git -C "$work" checkout -q -b main
  values_fixture > "$work/values-backend.yaml"
  values_fixture > "$work/values-frontend.yaml"
  git -C "$work" add -A
  git -C "$work" commit -q -m seed
  git -C "$work" push -q origin main 2> /dev/null
  git clone -q "$bare" "$other" 2> /dev/null
}

# run_promote: uruchamia skrypt w $work; ustawia $rc i $out.
run_promote() {
  rc=0
  out=$(cd "$work" && bash "$script" "$@" 2>&1) || rc=$?
}

head_of() { git -C "$1" rev-parse HEAD; }
commits_in() { git -C "$1" rev-list --count HEAD; }

# 1. Zmienia tylko image.tag, zachowuje komentarze, drugi tag: poza image: zostaje.
new_repos zmiana
run_promote "chore: promote" values-backend.yaml=1.2.3
[[ $rc -eq 0 ]] || fail "promote exit $rc: $out"
expected=$(values_fixture | sed 's/tag: 1.0.0 # pinned by promotion/tag: 1.2.3 # pinned by promotion/')
[[ "$(cat "$work/values-backend.yaml")" == "$expected" ]] || fail "unexpected file content: $(diff <(echo "$expected") "$work/values-backend.yaml")"
[[ "$(git -C "$bare" log -1 --format=%s main)" == "chore: promote" ]] || fail "commit not in bare"
[[ "$(git -C "$bare" log -1 --format='%an <%ae>' main)" == "platform-promote <platform-promote@users.noreply.github.com>" ]] \
  || fail "wrong author: $(git -C "$bare" log -1 --format='%an <%ae>' main)"

# 2. Ten sam tag nie tworzy commitu ani pusha.
before=$(git -C "$bare" rev-parse main)
run_promote "chore: promote" values-backend.yaml=1.2.3
[[ $rc -eq 0 ]] || fail "repeat exit $rc: $out"
[[ "$(git -C "$bare" rev-parse main)" == "$before" ]] || fail "repeat moved bare"
[[ "$(commits_in "$work")" -eq 2 ]] || fail "repeat created a commit"

# 3. Zły tag, pusty tag, ścieżka absolutna i z .. dają kod 2 i nic nie zmieniają.
new_repos odmowa
base=$(head_of "$work")
for bad in "values-backend.yaml=latest" "values-backend.yaml=" "values-backend.yaml=1.2" "values-backend.yaml=v1.2.3" \
  "values-backend.yaml=1.2.3-" "/etc/values.yaml=1.2.3" "../values-backend.yaml=1.2.3" "sub/../values-backend.yaml=1.2.3" \
  "=1.2.3" "values-backend.yaml"; do
  run_promote "chore: promote" "$bad"
  [[ $rc -eq 2 ]] || fail "'$bad' exit $rc, want 2: $out"
  [[ "$(head_of "$work")" == "$base" ]] || fail "'$bad' committed"
  [[ -z "$(git -C "$work" status --porcelain)" ]] || fail "'$bad' left changes"
done
run_promote "chore: promote"
[[ $rc -eq 2 ]] || fail "no pairs exit $rc, want 2"
run_promote "" values-backend.yaml=1.2.3
[[ $rc -eq 2 ]] || fail "empty message exit $rc, want 2"
run_promote "chore: promote" values-backend.yaml=1.2.3 values-frontend.yaml=latest
[[ $rc -eq 2 ]] || fail "one bad pair exit $rc, want 2"
[[ "$(cat "$work/values-backend.yaml")" == "$(values_fixture)" ]] || fail "one bad pair changed the good file"
run_promote "chore: promote" values-backend.yaml=1.2.3-rc.1
[[ $rc -eq 0 ]] || fail "prerelease tag exit $rc: $out"
grep -q 'tag: 1.2.3-rc.1' "$work/values-backend.yaml" || fail "prerelease not written"

# 4. Plik bez image.tag, z dwoma albo nieistniejący: kod 1 i brak commitu, także gdy drugi plik jest poprawny.
new_repos brak
printf 'image:\n  repository: x\nsidecar:\n  tag: 9.9.9\n' > "$work/no-tag.yaml"
printf 'image:\n  tag: 1.0.0\nimage:\n  tag: 1.0.1\n' > "$work/two-blocks.yaml"
printf 'sidecar:\n  tag: 9.9.9\n' > "$work/no-block.yaml"
git -C "$work" add -A && git -C "$work" commit -q -m fixtures
base=$(head_of "$work")
for f in no-tag.yaml two-blocks.yaml no-block.yaml missing.yaml; do
  run_promote "chore: promote" values-backend.yaml=1.2.3 "$f=1.2.3"
  [[ $rc -eq 1 ]] || fail "$f exit $rc, want 1: $out"
  [[ "$(head_of "$work")" == "$base" ]] || fail "$f committed"
  [[ -z "$(git -C "$work" status --porcelain)" ]] || fail "$f left changes"
done

# 5. Dwa pliki to jeden commit.
new_repos dwa
base=$(head_of "$work")
run_promote "chore: promote both" values-backend.yaml=2.0.0 values-frontend.yaml=3.0.0
[[ $rc -eq 0 ]] || fail "two files exit $rc: $out"
[[ "$(git -C "$bare" rev-list --count "$base..main")" -eq 1 ]] || fail "two files are not one commit"
grep -q '^  tag: 2.0.0' <<< "$(git -C "$bare" show main:values-backend.yaml)" || fail "backend not promoted"
grep -q '^  tag: 3.0.0' <<< "$(git -C "$bare" show main:values-frontend.yaml)" || fail "frontend not promoted"

# 6. Wyścig: obcy commit ląduje w bare między commitem a pushem; rebase i ponowienie zachowują obie zmiany.
install_race_hook() {
  printf '%s\n' "$1" > "$tmp/races"
  : > "$tmp/hook-runs"
  cat > "$work/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
echo run >> "$tmp/hook-runs"
left=\$(cat "$tmp/races")
if [[ \$left -gt 0 ]]; then
  echo \$((left - 1)) > "$tmp/races"
  git -C "$other" pull -q --rebase origin main
  echo "\$left" > "$other/foreign-\$left.txt"
  git -C "$other" add -A
  git -C "$other" commit -q -m "foreign \$left"
  git -C "$other" push -q origin main
fi
HOOK
  chmod +x "$work/.git/hooks/pre-push"
}

new_repos wyscig
install_race_hook 1
run_promote "chore: promote" values-backend.yaml=4.0.0
[[ $rc -eq 0 ]] || fail "race exit $rc: $out"
grep -q '^  tag: 4.0.0' <<< "$(git -C "$bare" show main:values-backend.yaml)" || fail "race lost the promotion"
subjects=$(git -C "$bare" log --format=%s main)
grep -qx "foreign 1" <<< "$subjects" || fail "race lost the foreign commit"
grep -qx "chore: promote" <<< "$subjects" || fail "race lost the promote commit"
[[ "$(wc -l < "$tmp/hook-runs" | tr -d ' ')" -eq 2 ]] || fail "expected 2 push attempts"

# 7. Trzy przegrane próby: kod 1, dokładnie 3 pushe.
new_repos zawsze
install_race_hook 3
run_promote "chore: promote" values-backend.yaml=4.0.0
[[ $rc -eq 1 ]] || fail "exhausted exit $rc, want 1: $out"
[[ "$(wc -l < "$tmp/hook-runs" | tr -d ' ')" -eq 3 ]] || fail "expected 3 push attempts"
! grep -q '^  tag: 4.0.0' <<< "$(git -C "$bare" show main:values-backend.yaml)" || fail "exhausted run still reached bare"

# 8. Płytki klon (checkout w promote.yml ma głębokość 1): wyścig z obcym commitem też zachowuje obie zmiany.
new_repos plytki
rm -r -f "$work"
git clone -q --depth 1 --branch main "file://$bare" "$work" 2> /dev/null
[[ "$(git -C "$work" rev-parse --is-shallow-repository)" == true ]] || fail "the work copy is not shallow"
install_race_hook 1
run_promote "chore: promote" values-backend.yaml=5.0.0
[[ $rc -eq 0 ]] || fail "shallow race exit $rc: $out"
grep -q '^  tag: 5.0.0' <<< "$(git -C "$bare" show main:values-backend.yaml)" || fail "shallow race lost the promotion"
subjects=$(git -C "$bare" log --format=%s main)
grep -qx "foreign 1" <<< "$subjects" || fail "shallow race lost the foreign commit"
grep -qx "chore: promote" <<< "$subjects" || fail "shallow race lost the promote commit"

echo "promote-image.test.sh: OK"
