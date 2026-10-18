#!/usr/bin/env bash
# README.md lists everything Platform publishes: every npm package, every Maven module and every
# reusable workflow. templates/README.md lists every canonical file under templates/.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

missing=()
for manifest in "$root"/frontend/packages/*/package.json; do
  name=$(node -p "require(process.argv[1]).name" "$manifest")
  grep -qF "\`$name\`" "$root/README.md" || missing+=("README.md: npm package $name")
done
for module in "$root"/gradle/*/; do
  module="${module%/}"; module="${module##*/}"
  grep -q 'maven-publish' "$root/gradle/$module/build.gradle.kts" 2>/dev/null || continue
  grep -qF "\`gradle/$module/\`" "$root/README.md" || missing+=("README.md: Maven module gradle/$module/")
done
for workflow in "$root"/.github/workflows/*.yml; do
  grep -q '^  workflow_call:' "$workflow" || continue
  name="${workflow##*/}"
  [[ "$name" == ci.yml ]] && continue # Platform's own CI; only release.yml calls it
  grep -qF "\`$name\`" "$root/README.md" || missing+=("README.md: reusable workflow $name")
done

# Canonical files: a file under jvm/ or roadmap/ is covered by its directory row, the rest by their own row.
while IFS= read -r path; do
  relative="${path#templates/}"
  case "$relative" in
    tests/* | README.md) continue ;;
    jvm/*) entry="jvm/$(cut -d/ -f2 <<<"$relative")/" ;;
    roadmap/*) entry="roadmap/" ;;
    *) entry="$relative" ;;
  esac
  grep -qF "\`$entry\`" "$root/templates/README.md" || missing+=("templates/README.md: $entry")
done < <(git -C "$root" ls-files templates)

if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Missing from the inventory:\n' >&2
  printf '  %s\n' "${missing[@]}" | sort -u >&2
  exit 1
fi
echo 'OK: README.md and templates/README.md list every published artifact and canonical file'
