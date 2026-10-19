#!/usr/bin/env bash
# Migracje wydania (migrations/): każda z test/migrations/<slug>/before daje after przez runner, drugi przebieg
# niczego nie zmienia, bramka SINCE wybiera właściwe migracje, a pełny bump od 1.5.26 wykonuje je z tarballa celu.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$here/bump-fixture.sh"
runner="$here/../migrations/run.sh"

# migrate <slug> <current> <target>: kopia before/ w katalogu roboczym, wynik runnera w $fixture_work/<slug>.out
migrate() {
  local tree="$fixture_work/tree-$1"
  rm -rf "$tree" && cp -R "$here/migrations/$1/before" "$tree"
  (cd "$tree" && PLATFORM_CANON="$here/migrations/$1/versions.json" bash "$runner" apply "$2" "$3") > "$fixture_work/$1.out"
  printf '%s\n' "$tree"
}

for slug in caller-packages-read runtime-image-27 drop-stale-overrides; do
  tree=$(migrate "$slug" 1.5.26 1.6.0)
  diff -r "$here/migrations/$slug/after" "$tree" || fail "$slug: before/ must become after/"
  grep -q "applied  .*$slug" "$fixture_work/$slug.out" || { cat "$fixture_work/$slug.out"; fail "$slug: the runner must report it applied"; }
  (cd "$tree" && PLATFORM_CANON="$here/migrations/$slug/versions.json" bash "$runner" apply 1.5.26 1.6.0) > "$fixture_work/$slug.again"
  diff -r "$here/migrations/$slug/after" "$tree" || fail "$slug: a second run must change nothing"
  if grep -q "applied  .*$slug" "$fixture_work/$slug.again"; then cat "$fixture_work/$slug.again"; fail "$slug: a second run must not apply it again"; fi
done

grep -qF ".github/workflows/flow.yml:2: add packages: read to \`permissions: { contents: read }\`" "$fixture_work/caller-packages-read.out" \
  || { cat "$fixture_work/caller-packages-read.out"; fail 'a flow-mapping permissions block must be left for a manual fix'; }
grep -qF "Dockerfile:1: move \`eclipse-temurin:26-jre-alpine\` to a Java 27 runtime" "$fixture_work/runtime-image-27.out" \
  || { cat "$fixture_work/runtime-image-27.out"; fail 'an image variant the migration does not know must be left for a manual fix'; }
grep -qF 'removed overrides.postcss: 8.4.31' "$fixture_work/drop-stale-overrides.out" || fail 'the removed overrides must be listed'

# Obraz migracji = ostatni FROM szablonu, z którego biorą go konsumenci.
template_image=$(sed -n -E 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "$here/../../../../templates/Dockerfile.backend" | tail -1)
grep -qx "RUNTIME_IMAGE=\"$template_image\"" "$here/../migrations/1.6.0-runtime-image-27.sh" \
  || fail "runtime-image-27 must move to $template_image, the final FROM of templates/Dockerfile.backend"

# Bramka SINCE: CUR < SINCE <= TARGET; every-* przy każdym bumpie.
tree=$(migrate caller-packages-read 1.6.0 1.6.1)
diff -r "$here/migrations/caller-packages-read/before" "$tree" >/dev/null || fail 'a bump from 1.6.0 must not run 1.6.0 migrations'
tree=$(migrate caller-packages-read 1.5.26 1.5.31)
diff -r "$here/migrations/caller-packages-read/before" "$tree" >/dev/null || fail 'a bump to 1.5.31 must not run 1.6.0 migrations'
tree=$(migrate drop-stale-overrides 1.6.0 1.6.1)
diff -r "$here/migrations/drop-stale-overrides/after" "$tree" || fail 'every-* migrations run on every bump'
files=$(cd "$here/migrations/runtime-image-27/before" && bash "$runner" files 1.5.26 1.6.0)
[[ "$files" == $'Dockerfile\nbackend/Dockerfile' ]] || fail "run.sh files must list what the migrations may change, got: $files"

# Pełny bump w kształcie Attestate (1.5.26): referencje, packages: read i obraz runtime w jednym przebiegu.
attestate() {
  mkdir -p "$1/backend"
  printf 'FROM eclipse-temurin:26-jre\nCOPY app.jar app.jar\n' > "$1/backend/Dockerfile"
  printf 'permissions:\n  contents: read\njobs:\n  backend:\n    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1\n' > "$1/.github/workflows/backend.yml"
}
export FAKE_MIGRATIONS="$here/../migrations"
dir=$(FIXTURE_EXTRA=attestate consumer attestate 1.5.26)
bump "$dir" --dry-run 1.6.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'the dry run of the Attestate bump must succeed'; }
grep -qF '+FROM sapmachine:27-jre' "$dir.log" || { cat "$dir.log"; fail 'the dry run must show the migrated Dockerfile'; }
[[ -z "$(git -C "$dir" status --porcelain)" ]] || fail 'the dry run must restore what the migrations changed'
bump "$dir" 1.6.0
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'the Attestate bump must succeed'; }
grep -qx 'FROM sapmachine:27-jre' "$dir/backend/Dockerfile" || fail 'the runtime image must move'
grep -qx '  packages: read' "$dir/.github/workflows/backend.yml" || fail 'the backend-ci caller must get packages: read'
grep -qF 'backend-ci.yml@v1.6.0' "$dir/.github/workflows/backend.yml" || fail 'the workflow ref must move to the exact target'
grep -qF 'applied  1.6.0-caller-packages-read' "$dir.log" || { cat "$dir.log"; fail 'the bump must list the applied migrations'; }

echo 'OK: upgrade migrations turn before/ into after/, are idempotent, honour SINCE and run from the target release'
