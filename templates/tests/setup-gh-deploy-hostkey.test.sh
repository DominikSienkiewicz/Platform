#!/usr/bin/env bash
# setup-gh-deploy.sh verifies the scanned host key against SSH_HOST_KEY_SHA256 before pushing anything,
# and exits non-zero when a gh call fails instead of ending with "Gotowe".
#
# Hermetic: gh and ssh-keyscan are stubs on PATH; the host key is a real ed25519 key generated here,
# so ssh-keygen computes a real fingerprint.
set -euo pipefail

CANON="$(cd "$(dirname "$0")/.." && pwd)/setup-gh-deploy.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { local message="$1"; echo "FAIL: $message"; echo "--- output ---"; cat "$OUT"; exit 1; }

ssh-keygen -q -t ed25519 -N '' -C host -f "$WORK/host_key"
FINGERPRINT="$(ssh-keygen -lf "$WORK/host_key.pub" | awk '{ print $2 }')"
KNOWN="fakehost $(cut -d' ' -f1,2 "$WORK/host_key.pub")"

BIN="$WORK/bin"
mkdir -p "$BIN"
ARGV_LOG="$WORK/gh-argv.log"
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$ARGV_LOG"
case "\$1 \$2" in
  "repo view") echo "owner/fake-repo"; exit 0 ;;
  "secret set") cat >/dev/null; exit "\${GH_SECRET_STATUS:-0}" ;;
  *) exit 0 ;;
esac
EOF
printf '#!/usr/bin/env bash\necho %q\n' "$KNOWN" > "$BIN/ssh-keyscan"
chmod +x "$BIN/gh" "$BIN/ssh-keyscan"

REPO="$WORK/repo"
mkdir -p "$REPO/scripts"
cp "$CANON" "$REPO/scripts/setup-gh-deploy.sh"
echo "SENTINEL_sshkey_private" > "$WORK/id_deploy"
OUT="$WORK/out.log"

# run <SSH_HOST_KEY_SHA256>: bootstraps the stub repo; sets RC.
run() {
  local expected="$1"
  cat > "$REPO/.secrets.local" <<EOF
GPR_USER=user
GPR_KEY=key
NPM_GH_TOKEN=npm
SSH_HOST=1.2.3.4
SSH_USER=deploy
SSH_KEY_FILE=$WORK/id_deploy
SSH_HOST_KEY_SHA256=$expected
GHCR_OWNER=owner
DEPLOY_PATH=/opt/app
EOF
  : > "$ARGV_LOG"
  RC=0
  PATH="$BIN:$PATH" GH_REPO=owner/fake-repo bash "$REPO/scripts/setup-gh-deploy.sh" > "$OUT" 2>&1 || RC=$?
}

# (a) the scanned key matches the fingerprint, with or without the SHA256: prefix
run "$FINGERPRINT"
[[ $RC -eq 0 ]] || fail "a matching host key must pass (exit $RC)"
grep -q '^secret set SSH_KNOWN_HOSTS' "$ARGV_LOG" || fail "a verified host key must be pushed"
run "${FINGERPRINT#SHA256:}"
[[ $RC -eq 0 ]] || fail "the fingerprint without its SHA256: prefix must pass (exit $RC)"

# (b) a mismatching fingerprint stops the script before any secret is pushed
run "SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
[[ $RC -ne 0 ]] || fail "a mismatching host key must exit non-zero"
if grep -q '^secret set' "$ARGV_LOG"; then fail "nothing may be pushed after a host key mismatch"; fi
grep -q 'matches SSH_HOST_KEY_SHA256' "$OUT" || fail "the mismatch must name SSH_HOST_KEY_SHA256"

# (c) an empty fingerprint is trust on first use: it passes with a warning
run ""
[[ $RC -eq 0 ]] || fail "an empty SSH_HOST_KEY_SHA256 must still bootstrap (exit $RC)"
grep -q 'trust on first use' "$OUT" || fail "an empty SSH_HOST_KEY_SHA256 must warn about trust on first use"

# (d) a failing gh secret set makes the script exit non-zero
GH_SECRET_STATUS=1 run "$FINGERPRINT"
[[ $RC -ne 0 ]] || fail "a failing gh secret set must exit non-zero"
if grep -q '^Gotowe' "$OUT"; then fail "a failed bootstrap must not end with Gotowe"; fi

echo "OK: the host key is verified before anything is pushed, and gh failures exit non-zero"
