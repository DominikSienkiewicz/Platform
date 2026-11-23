#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

owner=SeniorDeveloper-pl-Dominik-Sienkiewicz
for version in 2.0.0 1.13.1; do
  out="$tmp/consumer-$version"
  scope=@seniordeveloper-pl-dominik-sienkiewicz
  if [[ $version == 1.* ]]; then scope=@dominiksienkiewicz; fi
  bash "$root/scripts/new-consumer.sh" --name sample --package com.example.sample \
    --kind java-library --frontend next --platform-version "$version" --out "$out" > /dev/null
  web="$out/frontend"
  for workflow in backend-ci frontend-ci; do
    grep -qF "uses: $owner/Platform/.github/workflows/$workflow.yml@v$version" "$out/.github/workflows/ci.yml" \
      || fail "$version must call the organization's $workflow workflow"
  done
  grep -qxF "$scope:registry=https://npm.pkg.github.com" "$web/.npmrc" || fail "$version needs its published npm scope"
  for dependency in versions tsconfig eslint-config prettier-config tailwind-preset vitest-config; do
    jq -e --arg pkg "$scope/$dependency" --arg version "$version" '.devDependencies[$pkg] == $version' \
      "$web/package.json" > /dev/null || fail "$version must pin $scope/$dependency"
  done
  for entry in 'package.json:prettier-config' 'vitest.config.ts:vitest-config' 'tsconfig.json:tsconfig' \
    'eslint.config.mjs:eslint-config' 'src/app/globals.css:tailwind-preset'; do
    grep -qF "$scope/${entry#*:}" "$web/${entry%%:*}" || fail "$version imports the wrong package in ${entry%%:*}"
  done
  if [[ $version == 2.* ]]; then
    cmp -s "$root/templates/npmrc" "$web/.npmrc" || fail 'the organization registry must be the canonical template'
    grep -qF 'https://maven.pkg.github.com/seniordeveloper-pl-dominik-sienkiewicz/Platform' "$out/backend/settings.gradle.kts" \
      || fail 'the 2.x starter must resolve the organization Maven repository'
  fi
done
echo 'OK: generated consumers use the organization workflows and the package scope of their release'
