#!/usr/bin/env bash
# Nagłówek deploy.yml obiecuje cache: każdy build-push-action ma cache-from i cache-to w GHA z własnym scope,
# a bootJar biegnie po setup-gradle w tym samym jobie.
set -euo pipefail
workflow="$(cd "$(dirname "$0")/../.." && pwd)/.github/workflows/deploy.yml"
fail() { echo "FAIL: $*" >&2; exit 1; }

job=$(awk '/^  build-push:$/{p=1;next} /^  [a-z-]+:$/{p=0} p' "$workflow")
builds=$(grep -c 'uses: docker/build-push-action@' <<<"$job")
[[ $builds -ge 4 ]] || fail "expected the four image builds, found $builds"
[[ $(grep -c 'cache-from: type=gha,scope=' <<<"$job") -eq $builds ]] || fail 'every image build reads the GHA layer cache'
[[ $(grep -c 'cache-to: type=gha,mode=max,scope=' <<<"$job") -eq $builds ]] || fail 'every image build writes the GHA layer cache'
scopes=$(grep -oE 'cache-to: type=gha,mode=max,scope=.*$' <<<"$job" | sort | uniq -d)
[[ -z "$scopes" ]] || fail "two images share a cache scope: $scopes"
gradle=$(grep -n 'uses: gradle/actions/setup-gradle@' <<<"$job" | cut -d: -f1)
bootjar=$(grep -n 'name: Build bootJar' <<<"$job" | cut -d: -f1)
[[ -n "$gradle" && -n "$bootjar" && "$gradle" -lt "$bootjar" ]] || fail 'setup-gradle must run before the bootJar build'

echo 'OK: deploy.yml caches every image build per image and builds bootJar with the Gradle cache'
