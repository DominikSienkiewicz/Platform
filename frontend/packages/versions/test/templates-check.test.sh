#!/usr/bin/env bash
# platform-templates-check na lokalnych fiksturach (--canon-dir, bez sieci): DRIFT, MISSING, pliki opcjonalne,
# wydanie bez manifestu, nieczytelny kanon — zawsze kod 0. Do tego realny templates/manifest.json Platform
# i blok platform-bump, który odpala check obok siebie w trybie raportu.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
platform=$(cd "$here/../../../.." && pwd)
check="$here/../bin/templates-check.mjs"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

canon="$tmp/canon"; consumer="$tmp/consumer"
mkdir -p "$canon" "$consumer/scripts"
cat > "$canon/manifest.json" <<'JSON'
{ "files": [
  { "source": "a.sh", "target": "scripts/a.sh" },
  { "source": "b.sh", "target": "scripts/b.sh" },
  { "source": "c.sh", "target": "scripts/c.sh" },
  { "source": "opt.sh", "target": "scripts/opt.sh", "optional": true },
  { "source": "unused.sh", "target": "scripts/unused.sh", "optional": true }
] }
JSON
for f in a b c opt unused; do printf 'echo %s\n' "$f" > "$canon/$f.sh"; done
cp "$canon/a.sh" "$consumer/scripts/a.sh"
printf 'echo b, edited\n' > "$consumer/scripts/b.sh"
printf 'echo opt, edited\n' > "$consumer/scripts/opt.sh"

out=$(node "$check" --ref v9.9.9 --root "$consumer" --canon-dir "$canon") || fail 'drift must not change the exit code'
grep -qE '^  DRIFT +scripts/b\.sh$' <<<"$out" || fail "edited copy not reported: $out"
grep -qE '^  MISSING +scripts/c\.sh$' <<<"$out" || fail "missing copy not reported: $out"
grep -qE '^  DRIFT +scripts/opt\.sh$' <<<"$out" || fail "an optional file that exists is compared: $out"
if grep -qE 'scripts/(a|unused)\.sh' <<<"$out"; then fail "a matching or unused file must stay quiet: $out"; fi
grep -qF 'curl -fsSL https://raw.githubusercontent.com/DominikSienkiewicz/Platform/v9.9.9/templates/b.sh -o scripts/b.sh' <<<"$out" \
  || fail "no restore command for the pinned ref: $out"
grep -qF '3 of 4 templates are missing or differ' <<<"$out" || fail "unexpected summary: $out"

cp "$canon/b.sh" "$consumer/scripts/b.sh"; cp "$canon/c.sh" "$consumer/scripts/c.sh"; cp "$canon/opt.sh" "$consumer/scripts/opt.sh"
out=$(node "$check" --root "$consumer" --canon-dir "$canon")
grep -qF 'OK: 4 copied templates match the canon.' <<<"$out" || fail "matching copies must pass: $out"

mkdir -p "$tmp/old"
out=$(node "$check" --root "$consumer" --canon-dir "$tmp/old") || fail 'a release without a manifest must exit 0'
grep -qF 'predates the check' <<<"$out" || fail "a release without a manifest must say so: $out"

rm "$canon/a.sh"
out=$(node "$check" --root "$consumer" --canon-dir "$canon") || fail 'an unreadable canon must exit 0'
grep -qF 'Skipped: the canon could not be read' <<<"$out" || fail "an unreadable canon must be reported: $out"

if node "$check" --bogus x >/dev/null 2>&1; then fail 'an unknown option must be a usage error'; fi

real="$tmp/real"
node -e '
  const { mkdirSync, copyFileSync } = require("node:fs");
  const { dirname, join } = require("node:path");
  const [templates, root] = process.argv.slice(1);
  for (const { source, target } of require(join(templates, "manifest.json")).files) {
    mkdirSync(dirname(join(root, target)), { recursive: true });
    copyFileSync(join(templates, source), join(root, target));
  }
' "$platform/templates" "$real"
out=$(node "$check" --root "$real" --canon-dir "$platform/templates")
grep -qE 'OK: [0-9]+ copied templates match the canon\.' <<<"$out" || fail "templates/manifest.json names a file templates/ lacks: $out"

mkdir -p "$tmp/bin" "$tmp/link"
awk '/^# platform-bump:templates$/{p=1} p{print} /^# platform-bump:templates-end$/{exit}' "$here/../bin/platform-bump.sh" > "$tmp/bin/platform-bump.sh"
[[ -s "$tmp/bin/platform-bump.sh" ]] || fail 'the templates block markers are missing from platform-bump.sh'
printf 'console.log("check", process.argv.slice(2).join(" ")); process.exit(1);\n' > "$tmp/bin/templates-check.mjs"
ln -s "$tmp/bin/platform-bump.sh" "$tmp/link/platform-bump"
out=$(TARGET=9.9.9 bash -c 'set -euo pipefail; source "$0"' "$tmp/link/platform-bump") || fail 'a failing check must not fail the bump'
grep -qF 'check --ref v9.9.9' <<<"$out" || fail "platform-bump must run the check next to its real path for v\$TARGET: $out"

echo 'OK: platform-templates-check reports drift against the pinned canon and never fails the caller'
