#!/usr/bin/env bash
# check-canon-floors.py na SBOM-ach-atrapach. Przypadek z canon-cve-scan na b6877bf: canon-probe nie widział
# platform-bom, więc SBOM miał Jacksona 3.1.5 z Boota zamiast podłogi 3.1.8 z katalogu, a Grype zgłaszał
# CVE, których konsument nigdy nie dostaje. Do tego: każda podłoga CVE z gradle/bom jest sprawdzana.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$work/out.txt" >&2; exit 1; }

cat > "$work/libs.versions.toml" <<'TOML'
[versions]
springBoot = "4.1.1"
tomcat = "11.0.27"
jacksonBom = "3.1.8"
jackson2Bom = "2.21.8"
TOML
grep -v -E '^(tomcat|jacksonBom|jackson2Bom) =' "$work/libs.versions.toml" > "$work/old-libs.versions.toml"

# sbom <name> <group:name:version>...: SBOM CycloneDX z podanymi komponentami.
sbom() {
  local file="$work/$1.json"
  shift
  printf '%s\n' "$@" | python3 -c '
import json, sys
components = [dict(zip(("group", "name", "version"), line.split(":"))) for line in sys.stdin.read().split()]
print(json.dumps({"bomFormat": "CycloneDX", "components": components}))' > "$file"
}
run() { python3 "$root/scripts/check-canon-floors.py" "$work/$1.json" "$work/${2:-libs}.versions.toml" > "$work/out.txt" 2>&1; }

sbom boot-jackson tools.jackson.core:jackson-databind:3.1.5 tools.jackson.core:jackson-core:3.1.5 \
  com.fasterxml.jackson.core:jackson-annotations:2.21
if run boot-jackson; then fail 'Jackson 3.1.5 below the catalog floor 3.1.8 must fail'; fi
grep -qF 'tools.jackson.core:jackson-databind 3.1.5 is below the floor 3.1.8 (jacksonBom)' "$work/out.txt" \
  || fail 'the failure must name the component, its version, the floor and the catalog key'
grep -qF 'tools.jackson.core:jackson-core 3.1.5' "$work/out.txt" || fail 'every component below its floor must be named'

sbom at-floors tools.jackson.core:jackson-databind:3.1.8 com.fasterxml.jackson.core:jackson-databind:2.21.8 \
  com.fasterxml.jackson.core:jackson-annotations:2.21 org.apache.tomcat.embed:tomcat-embed-core:11.0.27
run at-floors || fail 'components at their floors must pass, and jackson-annotations is not checked'
grep -qF 'OK: 3 components meet the CVE floors of the catalog' "$work/out.txt" || fail 'the summary must count the checked components'

sbom above tools.jackson.core:jackson-databind:3.2.0 org.apache.tomcat.embed:tomcat-embed-el:11.0.30
run above || fail 'a version above its floor must pass'

if run boot-jackson old-libs; then :; else fail 'a catalog without the floors (an older tag) has nothing to enforce'; fi

# Każda podłoga CVE z gradle/bom (`because("CVE`) ma swój klucz w skrypcie. Klucz stoi w deklaracji nad
# `because`; sam powód cytuje wersję Boota (`libs.versions.springBoot`), która podłogą nie jest.
python3 "$root/scripts/check-canon-floors.py" --keys > "$work/keys.txt"
grep -B1 'because("CVE' "$root/gradle/bom/build.gradle.kts" | grep -v 'because(' \
  | grep -oE 'libs\.versions\.[A-Za-z0-9]+' | sed 's/^libs\.versions\.//' \
  | sort -u > "$work/bom-keys.txt"
[[ -s "$work/bom-keys.txt" ]] || fail 'gradle/bom/build.gradle.kts must declare at least one CVE floor'
missing=$(comm -23 "$work/bom-keys.txt" <(sort -u "$work/keys.txt"))
[[ -z "$missing" ]] || { echo "$missing" > "$work/out.txt"; fail 'every CVE floor of gradle/bom must be checked by check-canon-floors.py'; }

echo 'OK: check-canon-floors.py fails below a catalog CVE floor and covers every floor of platform-bom'
