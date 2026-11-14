#!/usr/bin/env bash
# Kanon frontendu przychodzi z `npm pack @dominiksienkiewicz/versions@<target>`. Brak wydania (E404) to ostrzeżenie,
# każdy inny błąd (401, sieć) kończy bump błędem z komunikatem npm zamiast cichego „stare wydanie platformy?”.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/bin" "$work/tool"
printf '#!/usr/bin/env bash\nexit 22\n' > "$work/bin/curl"
cat > "$work/bin/npm" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == pack ]]; then
  case "$FAKE_PACK" in
    E401) printf 'npm error code E401\nnpm error Unable to authenticate, need: Basic realm="GitHub Package Registry"\n' >&2 ;;
    E404) printf 'npm error code E404\nnpm error 404 Not Found - GET https://npm.pkg.github.com/@dominiksienkiewicz%%2fversions\n' >&2 ;;
  esac
  exit 1
fi
exit 0
STUB
chmod +x "$work/bin/curl" "$work/bin/npm"
cp "$here/../bin/platform-bump.sh" "$work/tool/platform-bump.sh"

bump() {
  local dir="$work/$1"
  mkdir -p "$dir/frontend"
  git -C "$dir" init -q
  printf '{ "devDependencies": { "@dominiksienkiewicz/versions": "1.5.31" } }\n' > "$dir/frontend/package.json"
  set +e
  (cd "$dir" && FAKE_PACK="$1" GPR_TOKEN=x PATH="$work/bin:$PATH" bash "$work/tool/platform-bump.sh" 9.9.9) > "$dir.log" 2>&1
  rc=$?
  set -e
  log="$dir.log"
}

bump E401
[[ $rc -ne 0 ]] || { cat "$log"; fail 'an authentication error must fail the bump'; }
grep -qF 'E401' "$log" || { cat "$log"; fail 'the failure must show the npm error'; }
if grep -qF 'stare wydanie' "$log"; then fail 'an authentication error is not an old release'; fi

bump E404
[[ $rc -eq 0 ]] || { cat "$log"; fail 'a release without the versions package only warns'; }
grep -qF 'is not published' "$log" || { cat "$log"; fail 'the warning must say the package is not published'; }

echo 'OK: platform-bump fails loudly on npm pack errors and only warns when the release lacks the package'
