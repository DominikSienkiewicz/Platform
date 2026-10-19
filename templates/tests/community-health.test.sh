#!/usr/bin/env bash
# Domyślne pliki społeczności (N-SHOW-13): templates/github/community/ to komplet dla repozytorium
# <właściciel>/.github, który GitHub stosuje do każdego publicznego repo właściciela bez własnego pliku.
# Test pilnuje: zestawu plików w układzie, którego GitHub oczekuje; treści neutralnej wobec repozytorium (bez
# słownika Platform, bez linków względnych); bramki formularzy (blank_issues_enabled: false i link do polityki
# bezpieczeństwa, u Platform i w domyślnych) oraz tego samego kanału zgłoszeń podatności; scripts/seed-community-health.sh
# (kopiuje zestaw do lokalnego klonu, odmawia nadpisania cudzych zmian, nie tworzy commita ani remote'a i nie dotyka
# sieci); kompletności docs/openssf-best-practices.md (każde kryterium poziomu passing raz, z policzonym podsumowaniem).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
community="$root/templates/github/community"
seed="$root/scripts/seed-community-health.sh"
assessment="$root/docs/openssf-best-practices.md"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- 1) Zestaw plików: dokładnie ten układ, który GitHub czyta z repozytorium .github ---
expected='.github/ISSUE_TEMPLATE/bug.yml
.github/ISSUE_TEMPLATE/config.yml
.github/ISSUE_TEMPLATE/feature-request.yml
.github/ISSUE_TEMPLATE/question.yml
.github/pull_request_template.md
CODE_OF_CONDUCT.md
CONTRIBUTING.md
README.md
SECURITY.md
SUPPORT.md'
actual=$(cd "$community" && find . -type f ! -name .DS_Store | sed 's|^\./||' | LC_ALL=C sort)
[[ "$actual" == "$expected" ]] || {
  diff <(echo "$expected") <(echo "$actual") >&2 || true
  fail 'templates/github/community/ must hold exactly the expected files'
}

# Pliki Platform zostają: własny plik repozytorium ma pierwszeństwo przed domyślnym.
for own in CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md .github/pull_request_template.md \
  .github/ISSUE_TEMPLATE/config.yml .github/ISSUE_TEMPLATE/bug.yml .github/ISSUE_TEMPLATE/library-request.yml \
  .github/ISSUE_TEMPLATE/adoption-request.yml; do
  [[ -f "$root/$own" ]] || fail "Platform keeps its own $own: a repository's own file overrides the default"
done

# --- 2) Bramka formularzy: puste zgłoszenia wyłączone i link do polityki bezpieczeństwa ---
check_issue_config() {
  grep -qx 'blank_issues_enabled: false' "$1" || fail "$2 must set blank_issues_enabled: false"
  grep -qE '^[[:space:]]+url: https://github\.com/[^ ]+/security/[^ ]+$' "$1" \
    || fail "$2 must link the security policy or the advisory form"
}
check_issue_config "$root/.github/ISSUE_TEMPLATE/config.yml" "Platform's issue config"
check_issue_config "$community/.github/ISSUE_TEMPLATE/config.yml" 'the default issue config'

for form in bug feature-request question; do
  file="$community/.github/ISSUE_TEMPLATE/$form.yml"
  for key in name description body; do
    grep -q "^$key:" "$file" || fail "$form.yml needs a top-level $key"
  done
  # Etykieta, której repozytorium nie ma, psuje formularz (dokumentacja GitHuba), więc domyślne jej nie ustawiają.
  if grep -q '^labels:' "$file"; then fail "$form.yml must not set labels: a default form cannot know the labels of a repository"; fi
done

# PyYAML bywa nieobecny na runnerze; gdy jest, formularze muszą być poprawnymi formularzami GitHuba.
if python3 -c 'import yaml' 2> /dev/null; then
  python3 - "$community/.github/ISSUE_TEMPLATE" << 'PY' || fail 'the default issue forms must be valid GitHub issue forms'
import pathlib
import sys

import yaml

for path in sorted(pathlib.Path(sys.argv[1]).glob("*.yml")):
    data = yaml.safe_load(path.read_text())
    if path.name == "config.yml":
        assert data["blank_issues_enabled"] is False, path
        assert data["contact_links"], path
        continue
    assert all(data.get(key) for key in ("name", "description", "body")), path
    ids = [item["id"] for item in data["body"] if "id" in item]
    assert len(ids) == len(set(ids)), f"{path}: ids must be unique"
    assert any(item["type"] != "markdown" for item in data["body"]), path
    for item in data["body"]:
        if item["type"] == "dropdown":
            assert item["attributes"]["options"], path
PY
fi

# --- 3) Treść neutralna wobec repozytorium ---
terms='platform|catalog|consumers?|convention|conventions|incubating|adoption|gradle|maven|npm|worktrees?|'
terms+='library[ -]request|Attestate|Azimuth|BookOfStyling|SkillSprint|Touchstone|AGENTS\.md|CLAUDE\.md'
while IFS= read -r file; do
  if found=$(grep -inwE "$terms" "$file"); then
    echo "$found" >&2
    fail "${file#"$root"/} mentions Platform-specific terms; the defaults must fit any repository"
  fi
  # Plik domyślny jest pokazywany w cudzych repozytoriach, gdzie link względny prowadzi donikąd.
  case "$file" in
    *.md)
      relative=$(grep -oE '\]\([^)]*\)' "$file" | grep -vE '^\]\((https://|#)' || true)
      [[ -z "$relative" ]] || fail "${file#"$root"/} has a relative link ($relative); use absolute URLs"
      ;;
  esac
done < <(find "$community" -type f ! -name .DS_Store)

# Ten sam kanał zgłoszeń podatności co w SECURITY.md Platform.
for policy in "$root/SECURITY.md" "$community/SECURITY.md"; do
  grep -q 'Private Vulnerability Reporting' "$policy" || fail "${policy#"$root"/} must name Private Vulnerability Reporting"
  grep -qF '**Report a vulnerability**' "$policy" || fail "${policy#"$root"/} must name the Report a vulnerability button"
done
grep -qF 'scripts/seed-community-health.sh' "$root/templates/README.md" || fail 'templates/README.md must list the seed script'

# --- 4) scripts/seed-community-health.sh ---
checkout="$tmp/dot-github"
git init -q "$checkout"

run_seed() { # <oczekiwany exit> <argumenty...>; wyjście w $tmp/out
  local want=$1 rc=0
  shift
  bash "$seed" "$@" > "$tmp/out" 2>&1 || rc=$?
  [[ "$rc" -eq "$want" ]] || { cat "$tmp/out" >&2; fail "seed $*: expected exit $want, got $rc"; }
}
layout() { (cd "$1" && find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort); }

run_seed 0 "$checkout"
[[ "$(layout "$checkout")" == "$expected" ]] || fail 'the seeded clone must have the layout GitHub reads'
while IFS= read -r relative; do
  cmp -s "$community/$relative" "$checkout/$relative" || fail "$relative must be copied byte for byte"
done <<< "$expected"
[[ -z "$(git -C "$checkout" remote)" ]] || fail 'the seed must not add a remote'
[[ -z "$(git -C "$checkout" rev-list --all)" ]] || fail 'the seed must not commit'

run_seed 0 "$checkout"
grep -q '^Copied 0 file' "$tmp/out" || { cat "$tmp/out" >&2; fail 'a second run must change nothing'; }

# Zmieniony plik w klonie i brakujący plik: bez --overwrite nic się nie kopiuje, z nim oba wracają do szablonu.
echo 'local edit' >> "$checkout/SUPPORT.md"
rm "$checkout/CONTRIBUTING.md"
run_seed 1 "$checkout"
grep -q 'SUPPORT.md' "$tmp/out" || fail 'the refusal must name the differing file'
[[ ! -e "$checkout/CONTRIBUTING.md" ]] || fail 'a refused run must copy nothing'
grep -q 'local edit' "$checkout/SUPPORT.md" || fail 'a refused run must leave the edited file alone'
run_seed 0 --overwrite "$checkout"
cmp -s "$community/SUPPORT.md" "$checkout/SUPPORT.md" || fail '--overwrite must restore the template'
[[ -f "$checkout/CONTRIBUTING.md" ]] || fail '--overwrite must restore a missing file'

# Odmowy: zły argument, katalog bez .git, brak katalogu, kopia samych szablonów.
run_seed 2
run_seed 2 --unknown "$checkout"
mkdir "$tmp/plain"
run_seed 1 "$tmp/plain"
[[ -z "$(find "$tmp/plain" -type f)" ]] || fail 'a directory that is not a clone must stay empty'
run_seed 1 "$tmp/missing"
mkdir -p "$tmp/templates-copy/.git" "$tmp/templates-copy/templates/github/community"
touch "$tmp/templates-copy/templates/github/community/CONTRIBUTING.md"
run_seed 1 "$tmp/templates-copy"
[[ ! -e "$tmp/templates-copy/SUPPORT.md" ]] || fail 'the templates themselves must not be seeded'
run_seed 0 --help
grep -q 'Usage:' "$tmp/out" || fail '--help must print the usage'

# Offline: żadnego klienta sieci ani polecenia git w kodzie skryptu (komentarze pomijamy)...
code=$(grep -vE '^[[:space:]]*#' "$seed")
publish_verb="pu""sh"
if grep -qE '(^|[^A-Za-z0-9_./-])(gh|curl|wget|ssh|scp|nc)([[:space:]]|$)' <<< "$code"; then
  fail 'the seed script must not call a network client'
fi
if grep -qE "(^|[^A-Za-z0-9_./-])git[[:space:]]+($publish_verb|pull|fetch|clone|remote|commit|init|add|config)" <<< "$code"; then
  fail 'the seed script must not run git commands that publish or change a repository'
fi
# ...i w działaniu: podstawione narzędzia zapisują wywołanie i kończą się błędem.
mkdir "$tmp/fakebin"
for tool in gh curl wget ssh scp nc git; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 99\n' "$tool" "$tmp/network.log" > "$tmp/fakebin/$tool"
  chmod +x "$tmp/fakebin/$tool"
done
mkdir "$tmp/offline"
mkdir "$tmp/offline/.git"
PATH="$tmp/fakebin:/usr/bin:/bin" bash "$seed" "$tmp/offline" > "$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail 'the seed must run without gh, curl or git'; }
[[ ! -s "$tmp/network.log" ]] || fail "the seed called a network or git tool: $(cat "$tmp/network.log")"
[[ "$(layout "$tmp/offline")" == "$expected" ]] || fail 'the offline run must seed the same layout'

# --- 5) docs/openssf-best-practices.md: każde kryterium poziomu passing raz, podsumowanie zgodne z tabelami ---
criteria='description_good interact contribution contribution_requirements floss_license floss_license_osi
license_location documentation_basics documentation_interface sites_https discussion english maintained
repo_public repo_track repo_interim repo_distributed version_unique version_semver version_tags release_notes
release_notes_vulns report_process report_tracker report_responses enhancement_responses report_archive
vulnerability_report_process vulnerability_report_private vulnerability_report_response build build_common_tools
build_floss_tools test test_invocation test_most test_continuous_integration test_policy tests_are_added
tests_documented_added warnings warnings_fixed warnings_strict know_secure_design know_common_errors
crypto_published crypto_call crypto_floss crypto_keylength crypto_working crypto_weaknesses crypto_pfs
crypto_password_storage crypto_random delivery_mitm delivery_unsigned vulnerabilities_fixed_60_days
vulnerabilities_critical_fixed no_leaked_credentials static_analysis static_analysis_common_vulnerabilities
static_analysis_fixed static_analysis_often dynamic_analysis dynamic_analysis_unsafe
dynamic_analysis_enable_assertions dynamic_analysis_fixed'
rows=$(awk -F'|' '/^\| `[a-z_0-9]+` \|/ { id = $2; status = $4; gsub(/[ `]/, "", id); gsub(/[ *]/, "", status); print id, status }' "$assessment")
expected_ids=$(tr ' ' '\n' <<< "$criteria" | grep -v '^$' | LC_ALL=C sort)
actual_ids=$(awk '{ print $1 }' <<< "$rows" | LC_ALL=C sort)
[[ "$actual_ids" == "$expected_ids" ]] || {
  diff <(echo "$expected_ids") <(echo "$actual_ids") >&2 || true
  fail 'the self-assessment must list each of the 67 passing criteria exactly once'
}
if grep -vE ' (Met|N/A|Notmet|Owneraction)$' <<< "$rows" > /dev/null; then fail 'every criterion needs a status: Met, N/A, Not met or Owner action'; fi
for pair in 'Met:Met' 'N/A:N/A' 'Notmet:Not met' 'Owneraction:Owner action'; do
  count=$(grep -c " ${pair%%:*}\$" <<< "$rows" || true)
  grep -qF "$count are **${pair#*:}**" "$assessment" || grep -qF "$count **${pair#*:}**" "$assessment" \
    || fail "the summary of the self-assessment must say $count ${pair#*:}"
done

echo 'OK: the community defaults, the seed script and the Best Practices self-assessment are complete, neutral and offline'
