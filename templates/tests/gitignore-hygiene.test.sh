#!/usr/bin/env bash
# No tracked file matches the ignore rules (Buildship output under gradle/*/bin/ once slipped in), and the
# OS and editor sections of Platform's .gitignore equal the canonical templates/gitignore/root.gitignore.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

fail() { local message="$1"; echo "FAIL: $message" >&2; exit 1; }

tracked=$(git -C "$root" ls-files -ci --exclude-standard)
[[ -z "$tracked" ]] || fail "tracked files match .gitignore; untrack them with git rm --cached:
$tracked"

# section <heading prefix> <file>: the lines of that section, up to the next blank line
section() {
  local heading="$1" file="$2"
  awk -v heading="$heading" 'index($0, heading) == 1 { inside = 1 } inside && /^$/ { exit } inside' "$file"
}
for heading in '# === OS junk ===' '# === IDE / editors ==='; do
  diff <(section "$heading" "$root/templates/gitignore/root.gitignore") <(section "$heading" "$root/.gitignore") \
    || fail "the '$heading' section of .gitignore differs from templates/gitignore/root.gitignore"
done
echo 'OK: no tracked file is ignored, and the OS and editor ignores match the canon'
