#!/usr/bin/env bash
# preview-on-consumer.sh <consumer-root> [--gradle "<tasks>"] [--frontend] [--staging <dir>] [--keep] — niewydana Platform na prawdziwym konsumencie
# (Decyzja 6), zanim niezmienny tag trafi do pięciu repo:
#   1. wersja podglądu <następny patch>-canary.<sha> — nie koliduje z wydaniem i nie pasuje do filtrów X.Y.Z;
#   2. moduły z gradle/maven-modules.txt publikowane do lokalnego repozytorium (-PplatformBundleRepository);
#      --staging <dir> używa wspólnego repozytorium i publikuje do niego tylko raz na wersję (scripts/canary.sh);
#   3. jednorazowy worktree konsumenta <consumer>/.worktrees/platform-preview-<sha> na HEAD (wykluczony przez
#      .git/info/exclude); główny checkout konsumenta zostaje nietknięty;
#   4. piny przepisane tym samym blokiem co platform-bump (marker platform-bump:backend-pins) i platformVersion=;
#   5. Gradle z -PplatformRepository, skryptem init dla pluginManagement (konsumenci, którzy go nie czytają),
#      --write-locks i --dependency-verification=lenient — dopuszczalne tylko w tym jednorazowym worktree.
# Domyślne zadania to szybki pas: compileJava compileTestJava platformDependencyCheck. --frontend dokłada frontend
# konsumenta: kanon z drzewa roboczego nakładany przez platform-versions-check --fix, potem sam check — zostaje to,
# czego bump by nie naprawił (zależność bez wpisu w kanonie). Worktree znika na końcu, chyba że --keep.
# Test: templates/tests/preview-on-consumer.test.sh.
set -euo pipefail
usage='Usage: scripts/preview-on-consumer.sh <consumer-root> [--gradle "<tasks>"] [--frontend] [--staging <dir>] [--keep]'
root=$(cd "$(dirname "$0")/.." && pwd)
gradlew=${PREVIEW_GRADLEW:-./gradlew}
consumer="" tasks="compileJava compileTestJava platformDependencyCheck" keep=false frontend=false shared_staging=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gradle) tasks=${2:?"--gradle needs the tasks. $usage"}; shift ;;
    --keep) keep=true ;;
    --frontend) frontend=true ;;
    --staging) shared_staging=${2:?"--staging needs a directory. $usage"}; shift ;;
    -*) echo "Unknown option $1. $usage" >&2; exit 2 ;;
    *) [[ -z "$consumer" ]] || { echo "$usage" >&2; exit 2; }; consumer=$1 ;;
  esac
  shift
done
[[ -n "$consumer" ]] || { echo "$usage" >&2; exit 2; }
consumer=$(cd "$consumer" && pwd -P)
git -C "$consumer" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$consumer is not a git repository." >&2; exit 2; }
[[ "$(git -C "$consumer" rev-parse --show-toplevel)" == "$consumer" ]] || { echo "Pass the consumer's root, not a subdirectory." >&2; exit 2; }

current=$(sed -n -E 's/^platformVersion=([0-9]+)\.([0-9]+)\.([0-9]+).*/\1 \2 \3/p' "$root/gradle/build-logic/gradle.properties")
read -r major minor patch <<<"$current"
sha=$(git -C "$root" rev-parse --short HEAD)
preview="$major.$minor.$((patch + 1))-canary.$sha"
if [[ -n "$shared_staging" ]]; then
  mkdir -p "$shared_staging"
  staging=$(cd "$shared_staging" && pwd -P)
else
  staging=$(mktemp -d)
fi
init_dir=$(mktemp -d)
init_script="$init_dir/init.gradle"
worktree="$consumer/.worktrees/platform-preview-$sha"
cleanup() {
  rm -rf "$init_dir"
  [[ -n "$shared_staging" ]] || rm -rf "$staging"
  if [[ "$keep" != true ]] && [[ -d "$worktree" ]]; then
    git -C "$consumer" worktree remove --force "$worktree"
  fi
}
trap cleanup EXIT

modules=$(awk '!/^#/ && NF { print $1 }' "$root/gradle/maven-modules.txt")
published="$staging/.published-$preview"
if [[ -f "$published" ]]; then
  echo "==> Platform $preview: reusing the Maven modules in $staging"
else
  echo "==> Platform $preview: publishing $(wc -w <<<"$modules" | tr -d ' ') Maven modules to $staging"
  for module in $modules; do
    (cd "$root/gradle/$module" && "$gradlew" --no-daemon -PplatformVersion="$preview" \
      -PplatformBundleRepository="$staging" publishAllPublicationsToBundleRepository)
  done
  touch "$published"
fi

exclude="$(git -C "$consumer" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
mkdir -p "$(dirname "$exclude")"
grep -qx '/.worktrees/' "$exclude" 2>/dev/null || echo '/.worktrees/' >> "$exclude"
[[ ! -e "$worktree" ]] || { echo "$worktree already exists; remove it or pass a different Platform commit." >&2; exit 2; }
git -C "$consumer" worktree add --quiet --detach "$worktree" HEAD

# Ten sam blok przepisywania pinów co platform-bump (jedno źródło wyrażeń), wycięty po markerach.
pins=$(awk '
  index($0, "# platform-bump:backend-pins ") == 1 { inside = 1; next }
  index($0, "# platform-bump:backend-pins-end") == 1 { inside = 0 }
  inside
' "$root/frontend/packages/versions/bin/platform-bump.sh")
[[ -n "$pins" ]] || { echo "platform-bump.sh has no backend-pins block between its markers." >&2; exit 1; }
# Ostatnia linia bloku to `[[ -f lockfile ]] && sed …`: bez lockfile'a kończy się kodem 1, co w bumpie nic nie znaczy.
(cd "$worktree" && TARGET="$preview" bash -c "set -euo pipefail; $pins
true")
for props in "$worktree/backend/gradle.properties" "$worktree/gradle.properties"; do
  [[ -f "$props" ]] && sed -i.bak -E "s/^platformVersion=.*/platformVersion=$preview/" "$props" && rm -f "$props.bak"
done

cat > "$init_script" <<GRADLE
beforeSettings { settings ->
    settings.pluginManagement.repositories.maven { url = uri("file://$staging") }
}
GRADLE
gradle_dir="$worktree"
[[ -f "$worktree/backend/settings.gradle.kts" ]] && gradle_dir="$worktree/backend"
read -r -a task_list <<<"$tasks"
echo "==> ${consumer##*/} on Platform $preview: ${task_list[*]}"
status=0
(cd "$gradle_dir" && "$gradlew" --no-daemon --init-script "$init_script" "${task_list[@]}" \
  -PplatformRepository="file://$staging" --write-locks --dependency-verification=lenient) || status=$?

if [[ $status -eq 0 ]]; then
  echo "==> ${consumer##*/} passes ${task_list[*]} on Platform $preview."
else
  echo "==> ${consumer##*/} fails ${task_list[*]} on Platform $preview (exit $status)." >&2
fi

if [[ "$frontend" == true ]] && [[ -f "$worktree/frontend/package.json" ]]; then
  check="$root/frontend/packages/versions/bin/check.mjs"
  frontend_status=0
  (cd "$worktree/frontend" && node "$check" --fix > /dev/null && node "$check") || frontend_status=$?
  if [[ $frontend_status -eq 0 ]]; then
    echo "==> ${consumer##*/} frontend passes platform-versions-check on the Platform $preview canon."
  else
    echo "==> ${consumer##*/} frontend fails platform-versions-check on the Platform $preview canon (exit $frontend_status)." >&2
    [[ $status -ne 0 ]] || status=$frontend_status
  fi
fi
if [[ "$keep" == true ]]; then
  echo "The preview worktree stays at $worktree; remove it with: git -C $consumer worktree remove --force $worktree"
fi
exit "$status"
