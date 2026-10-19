#!/usr/bin/env bash
# bump-report.py (N-REL-8): zmiany kanonu między dwoma wydaniami przecięte z tym, czego repo używa. Konsument woła
# libs.jsoup i backend-ci.yml, ma Dockerfile i react: raport wymienia dokładnie te aliasy, flaguje Dockerfile przy
# zmianie `java`, odkłada resztę do "Not used here" i daje ten sam wynik z zapasowym parserem TOML (Python 3.9).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "$OUT" >&2; exit 1; }

cat > "$tmp/old.toml" <<'TOML'
[versions]
java = "27"                 # toolchain
jsoup = "1.23.2"
wiremock = "3.13.2"
mapstruct = "1.6.3"

[libraries]
jsoup = { group = "org.jsoup", name = "jsoup", version.ref = "jsoup" }
wiremock-standalone = { group = "org.wiremock", name = "wiremock-standalone", version.ref = "wiremock" }
mapstruct = { group = "org.mapstruct", name = "mapstruct", version.ref = "mapstruct" }

[bundles]
modulith-web = [
  "jsoup",
]
TOML
sed -e 's/^java = "27"/java = "28"/' -e 's/^jsoup = "1.23.2"/jsoup = "1.24.0"/' -e 's/^wiremock = "3.13.2"/wiremock = "3.14.0"/' \
  -e '/^mapstruct = { /d' "$tmp/old.toml" > "$tmp/new.toml"
printf '{ "versions": { "react": "19.2.8", "vue": "3.5.0" } }\n' > "$tmp/old.json"
printf '{ "versions": { "react": "19.2.9", "vue": "3.6.0" } }\n' > "$tmp/new.json"
printf 'backend-ci.yml input gradle-task type=string default="build"\nsonar.yml input token type=string default=""\n' > "$tmp/old.txt"
printf 'backend-ci.yml input gradle-task type=string default="build"\nbackend-ci.yml input region type=string required=true\nsonar.yml input token type=string default=""\nsonar.yml input host type=string required=true\n' > "$tmp/new.txt"

repo="$tmp/repo"
mkdir -p "$repo/backend" "$repo/frontend" "$repo/.github/workflows"
printf 'plugins {\n  id("seniordev.java-conventions")\n}\ndependencies {\n  implementation(libs.jsoup)\n  implementation(libs.versions.jsoup.get())\n}\n' > "$repo/backend/build.gradle.kts"
printf 'FROM sapmachine:27-jre\n' > "$repo/backend/Dockerfile"
printf '{ "dependencies": { "react": "19.2.8" } }\n' > "$repo/frontend/package.json"
printf 'jobs:\n  ci:\n    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1.5.31\n' > "$repo/.github/workflows/ci.yml"

report() {
  python3 "$here/../bin/bump-report.py" --repo "$repo" --current 1.5.31 --target 1.6.0 \
    --catalog-old "$tmp/old.toml" --catalog-new "$tmp/new.toml" --canon-old "$tmp/old.json" --canon-new "$tmp/new.json" \
    --contract-old "$tmp/old.txt" --contract-new "$tmp/new.txt"
}
OUT=$(report)
section() { awk -v title="### $1" '$0 == title { inside = 1; next } /^### / { inside = 0 } inside && /^- /' <<<"$OUT"; }
affects=$(section "Affects this repo")
unused=$(section "Not used here")
actions=$(section "Consumer action required")

grep -qF '## Platform 1.5.31 → 1.6.0: impact on this repository' <<<"$OUT" || fail 'the report must name both releases'
grep -qF 'catalog `libs.versions.jsoup`: 1.23.2 → 1.24.0 (used as `libs.jsoup`, `libs.versions.jsoup`)' <<<"$affects" \
  || fail 'a version change must name the aliases the repo uses'
grep -qF 'catalog `libs.versions.java`: 27 → 28 (imposed by the Platform conventions)' <<<"$affects" \
  || fail 'the toolchain affects every build with the conventions'
grep -qF '`backend/Dockerfile`: its final `FROM` must run the new Java' <<<"$affects" || fail 'a java change must flag the Dockerfile'
grep -qF 'frontend canon `react`: 19.2.8 → 19.2.9' <<<"$affects" || fail 'a used frontend package affects the repo'
grep -qF '`backend-ci.yml` input `region` added (required)' <<<"$affects" || fail 'a called workflow affects the repo'
grep -qF 'wiremock' <<<"$affects" && fail 'an unused alias does not affect the repo'
grep -qF 'catalog `libs.versions.wiremock`: 3.13.2 → 3.14.0' <<<"$unused" || fail 'an unused version goes to Not used here'
grep -qF 'catalog `libs.mapstruct` removed' <<<"$unused" || fail 'a removed unused alias goes to Not used here'
grep -qF 'frontend canon `vue`' <<<"$unused" || fail 'an unused package goes to Not used here'
grep -qF '`sonar.yml` input `host` added (required)' <<<"$unused" || fail 'a workflow the repo does not call goes to Not used here'
grep -qF 'every caller of `backend-ci.yml` must pass the new required input `region`' <<<"$actions" || fail 'a used breaking change is an action'
grep -qF 'sonar.yml' <<<"$actions" && fail 'an action of an unused workflow is not this repo'"'"'s action'

FALLBACK=$(PLATFORM_TOML_FALLBACK=1 report)
[[ "$FALLBACK" == "$OUT" ]] || { OUT=$FALLBACK; fail 'the fallback TOML reader must give the same report'; }

OUT=$(python3 "$here/../bin/bump-report.py" --repo "$repo" --current 1.5.31 --target 1.6.0 --catalog-old "$tmp/old.toml" --catalog-new "$tmp/missing.toml")
grep -qF '> Note: the catalogs of both releases were not available' <<<"$OUT" || fail 'a missing release file must be named, not skipped silently'
echo 'OK: bump-report names what this repository uses, flags the Dockerfile on a java change and reads TOML on Python 3.9'
