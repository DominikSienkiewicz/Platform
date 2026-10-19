#!/usr/bin/env bash
# backend-ci.yml dołącza dokumentację Spring Modulith każdego modułu jako artefakt module-docs-<run id>.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
step=$(sed -n '/- name: Upload Spring Modulith documentation/,/retention-days/p' "$root/.github/workflows/backend-ci.yml")
[[ -n "$step" ]] || { echo 'FAIL: backend-ci.yml has no "Upload Spring Modulith documentation" step' >&2; exit 1; }
# shellcheck disable=SC2016 # literal GitHub expressions
for expected in 'name: module-docs-${{ github.run_id }}' 'path: ${{ inputs.working-directory }}/**/build/spring-modulith-docs/' 'if-no-files-found: ignore'; do
  grep -qF "$expected" <<<"$step" || { echo "FAIL: the module docs upload needs: $expected" >&2; exit 1; }
done
echo 'OK: backend-ci uploads the Spring Modulith documentation of every module'
