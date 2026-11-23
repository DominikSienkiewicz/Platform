#!/usr/bin/env bash
# platform-bump.sh — cienki STUB: deleguje do binu `platform-bump` pakietu @seniordeveloper-pl-dominik-sienkiewicz/versions.
# KANON LOGIKI bumpu żyje w Platform/frontend/packages/versions/bin/platform-bump.sh i dociera tu
# przez npm (frontend/node_modules/.bin) albo, w repo bez frontendu, z assetów GitHub Release — NIE wklejaj
# logiki bumpu do tego pliku ani do kopii per-repo.
# CANON: to jest kanon stuba (Platform/templates/platform-bump.sh) — kopiowany do `scripts/` każdego repo.
#
# Użycie:
#   ./scripts/platform-bump.sh            # podbij do najnowszej
#   ./scripts/platform-bump.sh 1.3.0      # podbij do konkretnej wersji
set -euo pipefail

# Stub żyje w `scripts/` repo konsumenta, a bin oczekuje CWD = root repo — operuj ZAWSZE tam,
# niezależnie skąd wywołano (bin dziedziczy CWD i przez `git rev-parse --show-toplevel`
# trafia we właściwe repo).
cd "$(dirname "$0")/.."

version=""
for argument in "$@"; do [[ "$argument" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && version="$argument"; done
legacy_install=false
if [[ -f frontend/node_modules/@dominiksienkiewicz/versions/package.json && ! -f frontend/node_modules/@seniordeveloper-pl-dominik-sienkiewicz/versions/package.json ]]; then
  legacy_install=true
fi
BIN="frontend/node_modules/.bin/platform-bump"
if [[ -x "$BIN" ]] && ! { [[ "$legacy_install" == true && -n "$version" && "${version%%.*}" -ge 2 ]]; }; then
  # Zainstalowany bin sam przekazuje sterowanie binowi wydania docelowego (handoff, N-DX-4).
  exec "$BIN" "$@"
fi

# Repo bez frontendu (N-DX-4): bin z assetów GitHub Release Platform — publiczne, bez npm i bez PAT-a, sprawdzone
# sumą z SHA256SUMS tego wydania. Wersja: argument X.Y.Z albo najnowsze wydanie; bin sam zostaje w bieżącym MAJOR
# i, gdy cel jest inny niż on, oddaje sterowanie binowi celu.
if [[ ! -f frontend/package.json ]] && ! grep -qs '^platformVersion=' backend/gradle.properties gradle.properties \
  && ! grep -qs 'pl.seniordeveloper:platform-catalog:' backend/settings.gradle.kts settings.gradle.kts; then
  echo "Brak $BIN — zainstaluj zależności frontendu: (cd frontend && npm install)." >&2
  echo "Bin istnieje od @dominiksienkiewicz/versions 1.3.8 — starszy pin w frontend/package.json" >&2
  echo "podbij ręcznie do najnowszej wersji platformy i powtórz npm install." >&2
  exit 1
fi
OWNER="SeniorDeveloper-pl-Dominik-Sienkiewicz"
releases="${PLATFORM_RELEASES_URL:-https://github.com/$OWNER/Platform/releases/download}"
api="${PLATFORM_RELEASES_API:-https://api.github.com/repos/$OWNER/Platform/releases/latest}"
proto() { [[ "$1" == file://* ]] && printf '=file' || printf '=https'; }
if [[ -z "$version" ]]; then
  version="$(curl -fsSL --proto "$(proto "$api")" "$api" 2>/dev/null | sed -n -E 's/.*"tag_name":[[:space:]]*"v([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' | head -1)"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "No frontend bin and no readable latest Platform release ($api)." >&2; exit 1; }
fi
cache_root="${PLATFORM_CLI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/platform-cli}"
scope=dominiksienkiewicz
if [[ "${version%%.*}" -ge 2 ]]; then
  scope=seniordeveloper-pl-dominik-sienkiewicz
  cache_root="$cache_root/verified-organization"
fi
cache="$cache_root/$version"
asset="$scope-versions-$version.tgz"
if [[ ! -f "$cache/package/bin/platform-bump.sh" ]]; then
  mkdir -p "$cache"
  work="$(mktemp -d "$cache/.install.XXXXXXXX")"
  trap 'rm -rf "$work"' EXIT
  if ! curl -fsSL --proto "$(proto "$releases")" "$releases/v$version/$asset" -o "$work/$asset" 2>/dev/null \
    || ! curl -fsSL --proto "$(proto "$releases")" "$releases/v$version/SHA256SUMS" -o "$work/SHA256SUMS" 2>/dev/null; then
    echo "No $BIN, and the release assets of Platform $version could not be downloaded from $releases/v$version." >&2
    exit 1
  fi
  expected="$(awk -v name="$asset" '$2 == name || $2 == "*" name { print $1 }' "$work/SHA256SUMS")"
  actual="$( (sha256sum "$work/$asset" 2>/dev/null || shasum -a 256 "$work/$asset") | awk '{ print $1 }')"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    echo "The release asset $asset of Platform $version does not match its SHA256SUMS; nothing was changed." >&2
    exit 1
  fi
  if [[ "${version%%.*}" -ge 2 ]]; then
    gh attestation verify "$work/$asset" --repo "$OWNER/Platform" --source-ref "refs/tags/v$version" --signer-workflow "$OWNER/Platform/.github/workflows/release.yml" >/dev/null
  fi
  tar -xzf "$work/$asset" -C "$work"
  [[ -f "$work/package/bin/platform-bump.sh" ]] || { echo "The release archive contains no platform-bump CLI." >&2; exit 1; }
  mv "$work/package" "$cache/" 2>/dev/null || [[ -f "$cache/package/bin/platform-bump.sh" ]]
  rm -rf "$work"
  trap - EXIT
fi
echo "==> Running the platform-bump of Platform $version from its release assets"
exec bash "$cache/package/bin/platform-bump.sh" "$@"
