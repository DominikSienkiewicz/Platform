#!/usr/bin/env bash
# consumer-audit.sh — macierz adopcji Platform w repozytoriach z scripts/consumers.txt: pin, wrapper
# Gradle, obraz runtime, artefakty JVM i npm, forma referencji reusable workflowów, caller
# platform-bump.yml i gałęzie Renovate.
#
#   scripts/consumer-audit.sh              # na żywo: wyłącznie GET przez `gh api` (wymaga `gh auth login`)
#   scripts/consumer-audit.sh --from DIR   # offline: DIR/<owner>/<name>/ z plikami repo i branches.txt
#
# Wynik opisuje prywatne repozytoria: uruchamiaj lokalnie przed ./release.sh, nie w CI ani w publicznym logu.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
consumers="${CONSUMERS_FILE:-$root/scripts/consumers.txt}"
platform_repo="${PLATFORM_REPO:-DominikSienkiewicz/Platform}"

usage() { echo "Usage: $0 [--from DIR]" >&2; }

repos() { grep -vE '^[[:space:]]*(#|$)' "$consumers"; }

# Pliki, z których audyt czyta: tylko one są pobierane.
relevant() {
  grep -E '(^|/)(settings\.gradle\.kts|gradle\.properties|build\.gradle\.kts|Dockerfile)$|(^|/)gradle/wrapper/gradle-wrapper\.properties$|^frontend/package\.json$|^\.github/workflows/[^/]+\.ya?ml$' || true
}

fetch() {
  local repo=$1 dir=$2 path
  mkdir -p "$dir"
  gh api --method GET "repos/$repo/git/trees/HEAD?recursive=1" \
    --jq '.tree[] | select(.type == "blob") | .path' > "$dir/.tree" || return 1
  while IFS= read -r path; do
    mkdir -p "$dir/$(dirname "$path")"
    gh api --method GET -H 'Accept: application/vnd.github.raw+json' "repos/$repo/contents/$path" > "$dir/$path" || return 1
  done < <(relevant < "$dir/.tree")
  gh api --method GET --paginate "repos/$repo/branches" --jq '.[].name' > "$dir/branches.txt" || return 1
}

# --- parsowanie: czyta wyłącznie katalog, bez sieci ---

files() { (cd "$1" && find . -type f -name "$2" | sed 's|^\./||' | sort); }

concat() {
  local f
  files "$1" "$2" | while IFS= read -r f; do cat "$1/$f"; done
}

# awk zamiast head: head kończy się wcześniej, a SIGPIPE w potoku z pipefail przerwałby skrypt.
first() { awk 'NR == 1'; }

shortest() { awk '{ print length($0) "\t" $0 }' | sort -n | first | cut -f2-; }

pin() {
  local version
  version=$(concat "$1" settings.gradle.kts | sed -nE 's/.*id\("seniordev\.settings-conventions"\)[[:space:]]+version[[:space:]]+"([^"]+)".*/\1/p' | first)
  [ -n "$version" ] || version=$(concat "$1" gradle.properties | sed -nE 's/^platformVersion[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' | first)
  echo "${version:-—}"
}

wrapper() {
  local file version=""
  file=$(files "$1" gradle-wrapper.properties | shortest)
  [ -z "$file" ] || version=$(sed -nE 's/^distributionUrl=.*gradle-([0-9][^-]*)-(bin|all)\.zip.*/\1/p' "$1/$file")
  echo "${version:-—}"
}

runtime_image() {
  local file image=""
  file=$(files "$1" Dockerfile | grep -v '^frontend/' | shortest || true)
  [ -z "$file" ] || image=$(sed -nE 's/^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]]+).*/\2/p' "$1/$file" | tail -1)
  if [ -n "$image" ]; then echo "\`$image\`"; else echo "—"; fi
}

uses_alias() {
  if concat "$1" build.gradle.kts | grep -F "libs.$2" > /dev/null; then echo yes; else echo no; fi
}

bundles() {
  local found
  found=$(concat "$1" build.gradle.kts | grep -oE 'libs\.bundles\.[A-Za-z0-9.]*[A-Za-z0-9]' | sed 's/^libs\.bundles\.//' | sort -u | paste -sd, - | sed 's/,/, /g')
  echo "${found:-—}"
}

npm_pins() {
  local manifest="$1/frontend/package.json"
  [ -f "$manifest" ] || { echo "no frontend"; return; }
  # shellcheck disable=SC2016 # ${…} to szablony JavaScriptu, nie rozwinięcia powłoki
  node -e '
    const manifest = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
    const byVersion = {};
    for (const deps of [manifest.dependencies, manifest.devDependencies]) {
      for (const [name, version] of Object.entries(deps ?? {})) {
        if (name.startsWith("@dominiksienkiewicz/")) (byVersion[version] ??= []).push(name.slice("@dominiksienkiewicz/".length));
      }
    }
    const pins = Object.entries(byVersion).map(([version, names]) => `${version}: ${names.sort().join(", ")}`);
    console.log(pins.join("; ") || "—");
  ' "$manifest"
}

workflow_uses() {
  [ -d "$1/.github/workflows" ] || return 0
  cat "$1"/.github/workflows/*.y*ml 2>/dev/null \
    | grep -ioE "uses:[[:space:]]*[\"']?$platform_repo/\.github/workflows/[^@[:space:]]+@[^[:space:]#\"']+" || true
}

workflow_refs() {
  local refs
  refs=$(workflow_uses "$1" | sed -E 's/.*@//' | sort -u | paste -sd, - | sed 's/,/, /g')
  echo "${refs:-—}"
}

bump_caller() {
  if workflow_uses "$1" | grep -iE '/platform-bump\.yml@' > /dev/null; then echo yes; else echo no; fi
}

renovate_branches() {
  if [ -f "$1/branches.txt" ]; then grep -c '^renovate/' "$1/branches.txt" || true; else echo "—"; fi
}

row() {
  local repo=$1 dir=$2
  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$repo" "$(pin "$dir")" "$(wrapper "$dir")" "$(runtime_image "$dir")" \
    "$(uses_alias "$dir" platform.test.fixtures)" "$(uses_alias "$dir" platform.security.starter)" \
    "$(bundles "$dir")" "$(npm_pins "$dir")" "$(workflow_refs "$dir")" "$(bump_caller "$dir")" \
    "$(renovate_branches "$dir")"
}

main() {
  local from="" repo
  case $# in
    0) ;;
    2) [ "$1" = --from ] || { usage; exit 2; }; from=$2 ;;
    *) usage; exit 2 ;;
  esac
  # Globalne, nie local: trap EXIT działa już po wyjściu z main.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  echo '| Repository | Platform pin | Gradle wrapper | Runtime image | test-fixtures | security-starter | Catalog bundles | npm packages | Workflow refs | platform-bump.yml | Renovate branches |'
  echo '|---|---|---|---|---|---|---|---|---|---|---|'
  while IFS= read -r repo; do
    if [ -n "$from" ]; then
      row "$repo" "$from/$repo"
    elif fetch "$repo" "$work/$repo" 2> "$work/error"; then
      row "$repo" "$work/$repo"
    else
      printf '| %s | not readable: %s |\n' "$repo" "$(tr '\n' ' ' < "$work/error" | cut -c1-120)"
    fi
  done < <(repos)
}

main "$@"
