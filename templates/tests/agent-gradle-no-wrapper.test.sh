#!/usr/bin/env bash
# agent-gradle.sh in a repository with neither ./gradlew nor backend/gradlew says so and exits 1,
# instead of failing on exec with "No such file or directory" (exit 127).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/scripts"
cp "$root/templates/agent-gradle.sh" "$tmp/scripts/agent-gradle.sh"
rc=0
out=$(bash "$tmp/scripts/agent-gradle.sh" build 2>&1) || rc=$?
[[ $rc -eq 1 ]] || { echo "FAIL: expected exit 1 without a wrapper, got $rc: $out" >&2; exit 1; }
grep -qF 'No gradlew in . or backend/' <<<"$out" || { echo "FAIL: the message must name both places: $out" >&2; exit 1; }
echo 'OK: agent-gradle.sh names the missing wrapper and exits 1'
