#!/usr/bin/env bash
# Wspólna atrapa dla testów całego binu platform-bump: zacommitowane repo konsumenta, stuby curl/npm sterowane
# zmiennymi FAKE_* i kopia binu bez sąsiedniego templates-check.mjs (bez sieci). Źródłowane, nie uruchamiane.
# shellcheck shell=bash
fixture_work=$(mktemp -d)
trap 'rm -rf "$fixture_work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$fixture_work/bin" "$fixture_work/tool"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../bin/platform-bump.sh" "$fixture_work/tool/platform-bump.sh"
# curl: /user odpowiada FAKE_USER_CODE (+ FAKE_SCOPES jako x-oauth-scopes), lista wersji = FAKE_VERSIONS,
# lista wycofanych = FAKE_YANKED; wszystko inne (notatki, katalog) kończy się błędem jak bez sieci.
cat > "$fixture_work/bin/curl" <<'STUB'
#!/usr/bin/env bash
out="" headers="" url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -D) headers="$2"; shift ;;
    -w | -H | -u | --proto | --proto-redir) shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
case "$url" in
  https://api.github.com/user)
    [[ -n "${FAKE_USER_CODE:-}" ]] || exit 22
    if [[ -n "$headers" ]]; then
      { printf 'HTTP/2 %s\r\n' "$FAKE_USER_CODE"; [[ -z "${FAKE_SCOPES+x}" ]] || printf 'x-oauth-scopes: %s\r\n' "$FAKE_SCOPES"; } > "$headers"
    fi
    printf '%s' "$FAKE_USER_CODE" ;;
  */packages/maven/*/versions) [[ -n "${FAKE_VERSIONS:-}" ]] || exit 22; printf '%s' "$FAKE_VERSIONS" > "$out" ;;
  */releases/yanked.txt) [[ -n "${FAKE_YANKED:-}" ]] || exit 22; printf '%s\n' "$FAKE_YANKED" > "$out" ;;
  *) exit 22 ;;
esac
STUB
# npm: pack daje tarball z versions.json (FAKE_PACK=ok; z migrations/, gdy FAKE_MIGRATIONS wskazuje katalog)
# albo błąd E401; install tylko zapisuje wywołanie.
cat > "$fixture_work/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "npm $*" >> "$FAKE_NPM_LOG"
if [[ "$1" == pack ]]; then
  [[ "${FAKE_PACK:-ok}" == ok ]] || { printf 'npm error code E401\n' >&2; exit 1; }
  while [[ $# -gt 0 && "$1" != --pack-destination ]]; do shift; done
  staging=$(mktemp -d)
  mkdir -p "$staging/package"
  printf '{ "versions": { "react": "19.2.8" } }\n' > "$staging/package/versions.json"
  [[ -z "${FAKE_MIGRATIONS:-}" ]] || cp -R "$FAKE_MIGRATIONS" "$staging/package/migrations"
  tar -czf "$2/dominiksienkiewicz-versions-9.9.9.tgz" -C "$staging" package
  rm -rf "$staging"
fi
exit 0
STUB
chmod +x "$fixture_work/bin/curl" "$fixture_work/bin/npm"
export FAKE_NPM_LOG="$fixture_work/npm.log"

# consumer <name> [pin]: zacommitowane repo z frontendem i callerem reusable workflowu na pinie (domyślnie
# 1.5.29); dodatkowe pliki przed commitem kładzie hook FIXTURE_EXTRA (funkcja dostaje katalog). Wypisuje ścieżkę.
consumer() {
  local dir="$fixture_work/$1" pin="${2:-1.5.29}"
  mkdir -p "$dir/frontend" "$dir/.github/workflows"
  git -C "$dir" init -q
  printf '{\n  "devDependencies": {\n    "@dominiksienkiewicz/versions": "%s",\n    "react": "19.0.0"\n  }\n}\n' "$pin" > "$dir/frontend/package.json"
  printf 'jobs:\n  frontend:\n    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v%s\n' "$pin" > "$dir/.github/workflows/ci.yml"
  [[ -z "${FIXTURE_EXTRA:-}" ]] || "$FIXTURE_EXTRA" "$dir"
  git -C "$dir" add -A
  git -C "$dir" -c user.name=t -c user.email=t@example.test commit -qm fixture
  printf '%s\n' "$dir"
}

# bump <dir> [args…]: uruchamia bin w repo; kod wyjścia w $rc, log w <dir>.log.
# shellcheck disable=SC2034 # rc i fixture_work czyta test, który źródłuje ten plik
bump() {
  local dir="$1"
  shift
  set +e
  (cd "$dir" && GPR_TOKEN=x PATH="$fixture_work/bin:$PATH" bash "$fixture_work/tool/platform-bump.sh" "$@") > "$dir.log" 2>&1
  rc=$?
  set -e
}
