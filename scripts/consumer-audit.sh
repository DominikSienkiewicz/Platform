#!/usr/bin/env bash
# consumer-audit.sh — macierz adopcji Platform w repozytoriach z scripts/consumers.txt: pin, wrapper
# Gradle, obraz runtime, artefakty JVM i npm, forma referencji reusable workflowów, caller
# platform-bump.yml i gałęzie Renovate.
#
#   scripts/consumer-audit.sh              # na żywo: wyłącznie GET przez `gh api` (wymaga `gh auth login`)
#   scripts/consumer-audit.sh --from DIR   # offline: DIR/<owner>/<name>/ z plikami repo i branches.txt
#   scripts/consumer-audit.sh --lag [--from DIR]   # zaległość: wydania i dni za najnowszym tagiem, pin na
#                                                  # wycofanym wydaniu (releases/yanked.txt), referencje @v1
#   scripts/consumer-audit.sh --adoption [--from DIR]  # status artefaktów (README) kontra realne użycie, warunek
#                                                  # wygaszenia v1 (Decyzja 3) i najstarszy pin = próg sprzątania
#
# Wynik opisuje prywatne repozytoria: uruchamiaj lokalnie przed ./release.sh, nie w CI ani w publicznym logu.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
consumers="${CONSUMERS_FILE:-$root/scripts/consumers.txt}"
platform_repo="${PLATFORM_REPO:-DominikSienkiewicz/Platform}"

usage() { echo "Usage: $0 [--lag | --adoption] [--from DIR]" >&2; }
readme="${PLATFORM_README:-$root/README.md}"
catalog="${PLATFORM_CATALOG:-$root/gradle/catalog/libs.versions.toml}"
packages_dir="${PLATFORM_PACKAGES:-$root/frontend/packages}"
# Tagi wydań i lista wycofanych z lokalnego checkoutu Platform (bez sieci); testy podają własne.
platform_git="${PLATFORM_GIT_DIR:-$root}"
yanked_file="${YANKED_FILE:-$root/releases/yanked.txt}"

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

# Wydania Platform od najstarszego: "<wersja> <data tagu YYYY-MM-DD>".
releases() {
  git -C "$platform_git" for-each-ref --format='%(refname:short) %(creatordate:short)' 'refs/tags/v*.*.*' \
    | sed -nE 's/^v([0-9]+\.[0-9]+\.[0-9]+) /\1 /p' | sort -t. -k1,1n -k2,2n -k3,3n
}

lag_row() {
  local repo=$1 dir=$2 version behind first_after days yanked refs
  version=$(pin "$dir")
  behind=$(releases | awk -v pin="$version" '
    function key(v, part) { split(v, part, "."); return part[1] * 1000000 + part[2] * 1000 + part[3] }
    pin != "—" && key($1) > key(pin) { n++ } END { print n + 0 }')
  first_after=$(releases | awk -v pin="$version" '
    function key(v, part) { split(v, part, "."); return part[1] * 1000000 + part[2] * 1000 + part[3] }
    pin != "—" && key($1) > key(pin) { print $2; exit }')
  days=0
  if [ -n "$first_after" ]; then
    days=$(( ($(date -u +%s) - $(date -u -j -f '%Y-%m-%d' "$first_after" +%s 2>/dev/null || date -u -d "$first_after" +%s)) / 86400 ))
  fi
  yanked=no
  if [ "$version" != "—" ] && [ -f "$yanked_file" ] && awk -v pin="$version" '{ sub(/#.*/, "") } $1 == pin { found = 1 } END { exit !found }' "$yanked_file"; then
    yanked=yes
  fi
  refs=$(workflow_uses "$dir" | grep -cE '@v1$' || true)
  printf '| %s | %s | %s | %s | %s | %s |\n' "$repo" "$version" "$behind" "$days" "$yanked" "$refs"
}

# Artefakty Platform: "maven <alias libs>", "bundle <nazwa z kropkami>", "npm <nazwa paczki>".
artifacts() {
  printf 'maven platform.test.fixtures\nmaven platform.security.starter\n'
  sed -n '/^\[bundles\]/,/^\[plugins\]/p' "$catalog" | sed -nE 's/^([a-z0-9-]+)[[:space:]]*=.*/\1/p' | tr '-' '.' | sed 's/^/bundle /'
  local manifest
  for manifest in "$packages_dir"/*/package.json; do
    [ -f "$manifest" ] && printf 'npm %s\n' "$(node -p 'require(process.argv[1]).name' "$manifest")"
  done
}

uses_artifact() {
  local dir=$1 kind=$2 name=$3
  case "$kind" in
    maven) [ "$(uses_alias "$dir" "$name")" = yes ] ;;
    bundle) bundles "$dir" | tr ',' '\n' | sed 's/^ *//' | grep -qxF "$name" ;;
    npm)
      [ -f "$dir/frontend/package.json" ] && node -e '
        const m = require(process.argv[1]);
        process.exit([m.dependencies, m.devDependencies].some((d) => d && process.argv[2] in d) ? 0 : 1);
      ' "$dir/frontend/package.json" "$name"
      ;;
  esac
}

# Status z README (sekcja "What it publishes"): wiersz z nazwą artefaktu (całym słowem, więc modulith-web nie łapie
# modulith-web-tests) i słowem incubating.
declared() {
  local pattern
  pattern="(^|[^a-z0-9-])${1//./\\.}([^a-z0-9-]|\$)"
  if grep -E "$pattern" "$readme" | grep -qi incubating; then echo incubating; else echo adopted; fi
}

label_of() {
  case "$1" in
    maven) printf 'platform-%s\n' "$(sed -e 's/^platform\.//' -e 's/\./-/g' <<<"$2")" ;;
    bundle) tr '.' '-' <<<"$2" ;;
    npm) printf '%s\n' "$2" ;;
  esac
}

adoption_report() {
  local dirs=$1 kind name label users verdict status oldest="" oldest_repo="" v1=0 v1_repos=0 repo dir version count
  echo '| Artifact | Declared | Used by | Verdict |'
  echo '|---|---|---|---|'
  while read -r kind name; do
    label=$(label_of "$kind" "$name")
    users=""
    while IFS='|' read -r repo dir; do
      if uses_artifact "$dir" "$kind" "$name"; then users+="${users:+, }$repo"; fi
    done < "$dirs"
    status=$(declared "$label")
    if [ "$status" = incubating ] && [ -n "$users" ]; then verdict="adopted: drop the incubating label"
    elif [ "$status" = adopted ] && [ -z "$users" ]; then verdict="no consumer: label it incubating"
    else verdict=ok; fi
    printf '| `%s` | %s | %s | %s |\n' "$label" "$status" "${users:-—}" "$verdict"
  done < <(artifacts)
  while IFS='|' read -r repo dir; do
    count=$(workflow_uses "$dir" | grep -cE '@v1$' || true)
    if [ "$count" -gt 0 ]; then v1=$((v1 + count)); v1_repos=$((v1_repos + 1)); fi
    version=$(pin "$dir")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if [ -z "$oldest" ] || [ "$(printf '%s\n%s\n' "$version" "$oldest" | sort -t. -k1,1n -k2,2n -k3,3n | first)" = "$version" ]; then
      oldest=$version
      oldest_repo=$repo
    fi
  done < "$dirs"
  echo ""
  if [ "$v1" -eq 0 ]; then
    echo "\`v1\` references: none, so \`move-v1\` can retire and \`v1\` can be frozen (Decision 3)."
  else
    echo "\`v1\` references: $v1 in $v1_repos repositories; \`move-v1\` retires when this reaches 0 (Decision 3)."
  fi
  if [ -n "$oldest" ]; then
    echo "Oldest pinned release: $oldest ($oldest_repo); keep it and every later version in GitHub Packages (C-12)."
  fi
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
  local from="" repo lag=0 adoption=0 render=row
  while [ $# -gt 0 ]; do
    case "$1" in
      --lag) lag=1 ;;
      --adoption) adoption=1 ;;
      --from) [ $# -ge 2 ] || { usage; exit 2; }; from=$2; shift ;;
      *) usage; exit 2 ;;
    esac
    shift
  done
  # Globalne, nie local: trap EXIT działa już po wyjściu z main.
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  if [ "$adoption" -eq 1 ]; then
    : > "$work/dirs"
    while IFS= read -r repo; do
      if [ -n "$from" ]; then
        printf '%s|%s\n' "$repo" "$from/$repo" >> "$work/dirs"
      elif fetch "$repo" "$work/$repo" 2> "$work/error"; then
        printf '%s|%s\n' "$repo" "$work/$repo" >> "$work/dirs"
      else
        echo "WARNING: $repo is not readable: $(tr '\n' ' ' < "$work/error" | cut -c1-120)" >&2
      fi
    done < <(repos)
    adoption_report "$work/dirs"
    return
  fi
  if [ "$lag" -eq 1 ]; then
    render=lag_row
    echo '| Repository | Platform pin | Releases behind | Days behind | Yanked pin | @v1 refs |'
    echo '|---|---|---|---|---|---|'
  else
    echo '| Repository | Platform pin | Gradle wrapper | Runtime image | test-fixtures | security-starter | Catalog bundles | npm packages | Workflow refs | platform-bump.yml | Renovate branches |'
    echo '|---|---|---|---|---|---|---|---|---|---|---|'
  fi
  while IFS= read -r repo; do
    if [ -n "$from" ]; then
      "$render" "$repo" "$from/$repo"
    elif fetch "$repo" "$work/$repo" 2> "$work/error"; then
      "$render" "$repo" "$work/$repo"
    else
      printf '| %s | not readable: %s |\n' "$repo" "$(tr '\n' ' ' < "$work/error" | cut -c1-120)"
    fi
  done < <(repos)
}

main "$@"
