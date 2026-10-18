#!/usr/bin/env bash
# Testcontainers (PlatformImages.java) and the local dev stack (infra/docker-compose.yml) must run the
# same pgvector and ollama tags. Renovate bumps both in one branch, so a hand edit of one file fails here.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)

files=(
  gradle/test-fixtures/src/main/java/pl/seniordeveloper/platform/testing/PlatformImages.java
  infra/docker-compose.yml
)

status=0
for image in pgvector/pgvector ollama/ollama; do
  expected=""
  expected_file=""
  for file in "${files[@]}"; do
    tags=$({ grep -o "$image:[A-Za-z0-9._-]*" "$root/$file" || true; } | sort -u)
    count=$(printf '%s' "$tags" | grep -c . || true)
    if [[ "$count" -ne 1 ]]; then
      printf '%s must name exactly one %s tag, found %s: %s\n' "$file" "$image" "$count" "$(printf '%s' "$tags" | tr '\n' ' ')" >&2
      status=1
    elif [[ -z "$expected" ]]; then
      expected="$tags"
      expected_file="$file"
    elif [[ "$tags" != "$expected" ]]; then
      printf '%s uses %s, but %s uses %s: bump both files together.\n' "$file" "$tags" "$expected_file" "$expected" >&2
      status=1
    fi
  done
done
exit "$status"
