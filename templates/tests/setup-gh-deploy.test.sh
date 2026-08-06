#!/usr/bin/env bash
# Test template'u setup-gh-deploy.sh (kanon: Platform/templates/setup-gh-deploy.sh).
#
# Hermetyczny (bez sieci/gh): `gh` i `ssh-keyscan` to stuby na PATH nagrywające wywołania.
# Sprawdzamy KONTRAKT: pushnięte nazwy sekretów/zmiennych = kontrakt reusable deploy.yml,
# wartości sekretów idą przez STDIN (nie argv), a SSH_KNOWN_HOSTS pochodzi z ssh-keyscan.
set -euo pipefail

CANON="$(cd "$(dirname "$0")/.." && pwd)/setup-gh-deploy.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# --- stuby na PATH ---
BIN="$WORK/bin"; mkdir -p "$BIN"
ARGV_LOG="$WORK/gh-argv.log"; STDIN_LOG="$WORK/gh-stdin.log"
: >"$ARGV_LOG"; : >"$STDIN_LOG"

cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$ARGV_LOG"
case "\$1 \$2" in
  "auth status"|"api "*|"secret list"|"variable list") exit 0 ;;
  "repo view") echo "owner/fake-repo"; exit 0 ;;
  "secret set") name="\$3"; body="\$(cat)"; printf '%s=%s\n' "\$name" "\$body" >> "$STDIN_LOG"; exit 0 ;;
  "variable set") shift 2; name="\$1"; printf 'VAR %s\n' "\$name" >> "$STDIN_LOG"; exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$BIN/ssh-keyscan" <<'EOF'
#!/usr/bin/env bash
echo "fakehost ssh-ed25519 AAAAC3NzaFAKEKEY"
EOF
chmod +x "$BIN/gh" "$BIN/ssh-keyscan"

# --- fake repo z kopią skryptu w scripts/ + wartościami-sentinelami ---
REPO="$WORK/repo"; mkdir -p "$REPO/scripts"
cp "$CANON" "$REPO/scripts/setup-gh-deploy.sh"; chmod +x "$REPO/scripts/setup-gh-deploy.sh"
KEYFILE="$WORK/id_deploy"; echo "SENTINEL_sshkey_private" > "$KEYFILE"
cat > "$REPO/.secrets.local" <<EOF
GPR_USER=SENTINEL_gpruser
GPR_KEY=SENTINEL_gprkey
NPM_GH_TOKEN=SENTINEL_npm
SSH_HOST=1.2.3.4
SSH_USER=deployuser
SSH_KEY_FILE=$KEYFILE
GHCR_OWNER=SENTINEL_owner
DEPLOY_PATH=/opt/app
EOF

PATH="$BIN:$PATH" GH_REPO=owner/fake-repo "$REPO/scripts/setup-gh-deploy.sh" >/dev/null 2>&1

fail() { local message="$1"; echo "FAIL: $message"; exit 1; }

# 1) wszystkie sekrety kontraktu pushnięte (po nazwie)
for s in GPR_USER GPR_KEY NPM_GH_TOKEN SSH_HOST SSH_USER SSH_KEY SSH_KNOWN_HOSTS; do
  grep -qE "^secret set $s( |\$)" "$ARGV_LOG" || fail "sekret $s nie ustawiony"
done
# 2) wszystkie zmienne kontraktu pushnięte
for v in GHCR_OWNER DEPLOY_PATH; do
  grep -qE "^variable set $v( |\$)" "$ARGV_LOG" || fail "zmienna $v nie ustawiona"
done
# 3) wartości sekretów NIE trafiły do argv (idą przez stdin)
grep -qE 'SENTINEL_(gprkey|npm|sshkey_private|gpruser)' "$ARGV_LOG" \
  && fail "wartość sekretu wyciekła do argv (powinna iść przez stdin)"
grep -q 'GPR_KEY=SENTINEL_gprkey' "$STDIN_LOG" || fail "wartość GPR_KEY nie przekazana przez stdin"
grep -q 'SSH_KEY=SENTINEL_sshkey_private' "$STDIN_LOG" || fail "SSH_KEY nie wczytany z pliku przez stdin"
# 4) SSH_KNOWN_HOSTS pochodzi z ssh-keyscan
grep -q 'SSH_KNOWN_HOSTS=fakehost ssh-ed25519 AAAAC3NzaFAKEKEY' "$STDIN_LOG" \
  || fail "SSH_KNOWN_HOSTS nie pochodzi z ssh-keyscan"

echo "OK: kontrakt sekretów/zmiennych pushnięty; wartości przez stdin; SSH_KNOWN_HOSTS z ssh-keyscan"
