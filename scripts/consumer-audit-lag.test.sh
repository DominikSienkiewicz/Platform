#!/usr/bin/env bash
# consumer-audit.sh --lag na fiksturach, bez sieci: wydania i dni za najnowszym tagiem z atrapy repo Platform,
# pin na wycofanym wydaniu z atrapy releases/yanked.txt i liczba referencji @v1.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; echo "$out" >&2; exit 1; }

platform="$work/platform"
git init -q -b main "$platform"
git -C "$platform" config user.name t
git -C "$platform" config user.email t@example.invalid
for release in 1.5.26:2026-09-10 1.5.30:2026-09-25 1.5.31:2026-10-01; do
  GIT_COMMITTER_DATE="${release#*:}T12:00:00Z" git -C "$platform" commit -q --allow-empty -m "${release%%:*}"
  GIT_COMMITTER_DATE="${release#*:}T12:00:00Z" git -C "$platform" tag -a "v${release%%:*}" -m "Platform ${release%%:*}"
done
printf '# yanked\n1.5.30 plugin markers missing; use 1.5.31\n' > "$work/yanked.txt"

repos="$work/repos"
put() { mkdir -p "$(dirname "$repos/$1")"; cat > "$repos/$1"; }
put acme/old/backend/settings.gradle.kts <<'EOF'
plugins { id("seniordev.settings-conventions") version "1.5.26" }
EOF
put acme/old/.github/workflows/ci.yml <<'EOF'
jobs:
  a:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v1
  b:
    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v1
EOF
put acme/yanked/backend/gradle.properties <<'EOF'
platformVersion=1.5.30
EOF
put acme/current/backend/gradle.properties <<'EOF'
platformVersion=1.5.31
EOF
printf 'acme/old\nacme/yanked\nacme/current\n' > "$work/consumers.txt"

out=$(CONSUMERS_FILE="$work/consumers.txt" PLATFORM_GIT_DIR="$platform" YANKED_FILE="$work/yanked.txt" \
  bash "$root/scripts/consumer-audit.sh" --lag --from "$repos")
since=$(( ($(date -u +%s) - $(date -u -j -f '%Y-%m-%d' 2026-09-25 +%s 2>/dev/null || date -u -d 2026-09-25 +%s)) / 86400 ))
since_last=$(( ($(date -u +%s) - $(date -u -j -f '%Y-%m-%d' 2026-10-01 +%s 2>/dev/null || date -u -d 2026-10-01 +%s)) / 86400 ))
grep -qxF '| Repository | Platform pin | Releases behind | Days behind | Yanked pin | @v1 refs |' <<<"$out" || fail 'the lag table needs its header'
grep -qxF "| acme/old | 1.5.26 | 2 | $since | no | 2 |" <<<"$out" || fail 'a pin two releases behind, with two @v1 refs'
grep -qxF "| acme/yanked | 1.5.30 | 1 | $since_last | yes | 0 |" <<<"$out" || fail 'a pin on a yanked release must be flagged'
grep -qxF '| acme/current | 1.5.31 | 0 | 0 | no | 0 |' <<<"$out" || fail 'the newest pin is not behind'

echo 'OK: consumer-audit --lag reports release lag, yanked pins and @v1 references'
