#!/usr/bin/env bash
# scripts/preview-on-consumer.sh na atrapach: gradlew (PREVIEW_GRADLEW) zapisuje swoje wywołania, konsument to
# zacommitowane repo z dosłownymi pinami. Sprawdza wersję podglądu, publikację czterech modułów, argumenty Gradle
# konsumenta, przepisane piny w jednorazowym worktree i nietknięty główny checkout.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; echo "--- output ---" >&2; cat "$tmp/out" >&2; exit 1; }
: > "$tmp/out"

cat > "$tmp/gradlew" <<'STUB'
#!/usr/bin/env bash
printf '%s | %s\n' "$PWD" "$*" >> "$FAKE_LOG"
if [[ "$*" == *platformDependencyCheck* ]]; then
  cp settings.gradle.kts "$FAKE_SEEN"
  exit "${FAKE_CONSUMER_RC:-0}"
fi
exit 0
STUB
chmod +x "$tmp/gradlew"
export PREVIEW_GRADLEW="$tmp/gradlew" FAKE_LOG="$tmp/gradle.log" FAKE_SEEN="$tmp/seen-settings.gradle.kts"

consumer="$tmp/azimuth"
git init -q -b main "$consumer"
git -C "$consumer" config user.name t
git -C "$consumer" config user.email t@example.invalid
mkdir -p "$consumer/backend"
cat > "$consumer/backend/settings.gradle.kts" <<'KTS'
plugins {
	id("seniordev.settings-conventions") version "1.5.30"
}
dependencyResolutionManagement {
	versionCatalogs { create("libs") { from("pl.seniordeveloper:platform-catalog:1.5.30") } }
}
KTS
git -C "$consumer" add -A
git -C "$consumer" commit -q -m initial

sha=$(git -C "$root" rev-parse --short HEAD)
current=$(sed -n 's/^platformVersion=//p' "$root/gradle/build-logic/gradle.properties")
IFS=. read -r major minor patch <<<"$current"
preview="$major.$minor.$((patch + 1))-canary.$sha"

bash "$root/scripts/preview-on-consumer.sh" "$consumer" > "$tmp/out" 2>&1 || fail 'a passing consumer must exit 0'
modules=$(awk '!/^#/ && NF { print $1 }' "$root/gradle/maven-modules.txt")
grep -qF "==> Platform $preview: publishing $(wc -w <<<"$modules" | tr -d ' ') Maven modules" "$tmp/out" || fail "the preview version must be $preview"
for module in $modules; do
  grep -qE "/gradle/$module \| --no-daemon -PplatformVersion=$preview -PplatformBundleRepository=.* publishAllPublicationsToBundleRepository$" "$FAKE_LOG" \
    || { cat "$FAKE_LOG"; fail "gradle/$module must be published at the preview version"; }
done
consumer_call=$(grep -F "platform-preview-$sha/backend |" "$FAKE_LOG") || { cat "$FAKE_LOG"; fail 'Gradle must run in the backend of the preview worktree'; }
for argument in '--init-script' 'compileJava compileTestJava platformDependencyCheck' '-PplatformRepository=file://' \
  '--write-locks' '--dependency-verification=lenient'; do
  grep -qF -- "$argument" <<<"$consumer_call" || fail "the consumer run must pass $argument"
done
grep -qF "id(\"seniordev.settings-conventions\") version \"$preview\"" "$FAKE_SEEN" || fail 'the settings plugin pin must be rewritten'
grep -qF "platform-catalog:$preview\")" "$FAKE_SEEN" || fail 'the catalog pin must be rewritten'
[[ ! -d "$consumer/.worktrees/platform-preview-$sha" ]] || fail 'the preview worktree must be removed'
[[ -z "$(git -C "$consumer" status --porcelain)" ]] || fail 'the primary checkout must stay untouched'
[[ "$(git -C "$consumer" worktree list | grep -c .)" -eq 1 ]] || fail 'no worktree may stay registered'
grep -qx '/.worktrees/' "$consumer/.git/info/exclude" || fail '.worktrees/ must be excluded locally'

: > "$FAKE_LOG"
if FAKE_CONSUMER_RC=1 bash "$root/scripts/preview-on-consumer.sh" "$consumer" --gradle 'check platformDependencyCheck' --keep > "$tmp/out" 2>&1; then
  fail 'a failing consumer must fail the preview'
fi
grep -qF "fails check platformDependencyCheck on Platform $preview" "$tmp/out" || fail 'the failure must name the tasks and version'
[[ -d "$consumer/.worktrees/platform-preview-$sha" ]] || fail '--keep must keep the worktree'
grep -qF 'The preview worktree stays at' "$tmp/out" || fail '--keep must say where the worktree is'
git -C "$consumer" worktree remove --force "$consumer/.worktrees/platform-preview-$sha"

if bash "$root/scripts/preview-on-consumer.sh" "$tmp" > "$tmp/out" 2>&1; then fail 'a directory outside git must be refused'; fi

echo 'OK: preview-on-consumer publishes a canary and checks a consumer in a throwaway worktree'
