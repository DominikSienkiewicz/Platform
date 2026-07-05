#!/usr/bin/env bash
# setup-gh-deploy.sh — push the GitHub Actions secrets + variables that the reusable
# deploy workflow (DominikSienkiewicz/Platform/.github/workflows/deploy.yml@v1) needs,
# from a LOCAL git-ignored file. Secret VALUES never pass through an agent and are never
# echoed — you fill `.secrets.local` and run this yourself.
#
# CANON: this file lives in Platform/templates/setup-gh-deploy.sh — do not edit per-repo
# copies; edit here and re-sync to each consumer's scripts/ (see templates/README.md).
#
# Contract pushed (must match the reusable deploy.yml):
#   secrets:   GPR_USER GPR_KEY NPM_GH_TOKEN SSH_HOST SSH_USER SSH_KEY SSH_KNOWN_HOSTS
#   variables: GHCR_OWNER DEPLOY_PATH
# SSH_KEY is read from a file (SSH_KEY_FILE); SSH_KNOWN_HOSTS is generated with ssh-keyscan.
# GITHUB_TOKEN is provided automatically by Actions — not bootstrapped here.
#
# Usage:
#   cp .secrets.local.example .secrets.local   # then fill in real values
#   ./scripts/setup-gh-deploy.sh
#   ./scripts/setup-gh-deploy.sh --gen-key       # generate an ed25519 deploy key if missing
#   ./scripts/setup-gh-deploy.sh --with-release  # also create branch `release` + protection
#   GH_REPO=owner/repo ./scripts/setup-gh-deploy.sh   # force target repo
#
# Requires: gh CLI authenticated (`gh auth status`) with ADMIN on the repo and `repo` scope.
set -euo pipefail

ENVFILE=""
GEN_KEY=0
WITH_RELEASE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --gen-key) GEN_KEY=1; shift ;;
    --with-release) WITH_RELEASE=1; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -z "$ENVFILE" ]; then ENVFILE="$1"; else echo "unexpected argument: $1" >&2; exit 2; fi
      shift ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # script lives in <repo>/scripts/
ENVFILE="${ENVFILE:-$ROOT/.secrets.local}"

command -v gh >/dev/null || { echo "Brak gh CLI. https://cli.github.com/" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh nie zalogowany — uruchom: gh auth login" >&2; exit 1; }
[ -f "$ENVFILE" ] || { echo "Brak $ENVFILE — skopiuj z .secrets.local.example i wypełnij." >&2; exit 1; }

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
[ -n "$REPO" ] || { echo "Nie wykryto repo. Ustaw: GH_REPO=owner/repo $0" >&2; exit 1; }
echo "Repo docelowe: $REPO"

# Preflight: confirm we can write Actions secrets (admin + right repo). Fail fast & clearly.
if ! gh api "repos/$REPO/actions/secrets/public-key" >/dev/null 2>&1; then
  cat >&2 <<EOF
BŁĄD: brak dostępu do sekretów Actions w '$REPO' (HTTP 404/403).
  - poprawna nazwa repo?   gh repo view --json nameWithOwner -q .nameWithOwner
  - właściwe konto z ADMIN? gh auth status
  - scope 'repo'?           gh auth refresh -s repo
  - wymuszenie repo:        GH_REPO=owner/repo $0
EOF
  exit 1
fi

# Parse KEY=VALUE safely (NEVER `source` — the file must not execute code): strip full-line
# comments, blanks, inline ' # comment', surrounding whitespace/quotes. SSH_KEY is read from a file.
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line//[[:space:]]/}" ]] && continue
  case "$line" in *=*) ;; *) continue ;; esac
  k="${line%%=*}"; k="$(printf '%s' "$k" | tr -d '[:space:]')"
  v="${line#*=}"
  v="$(printf '%s' "$v" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  v="${v%\"}"; v="${v#\"}"
  export "VAL_$k=$v"
done < "$ENVFILE"

set_secret() { # name value — value via stdin, never on the command line
  local n="$1" val="${2:-}"
  [ -n "$val" ] || { echo "  secret   $n — pominięto (PUSTE w $ENVFILE)"; return; }
  if printf '%s' "$val" | gh secret set "$n" -R "$REPO" >/dev/null 2>&1; then
    echo "  secret   $n ✓"
  else echo "  secret   $n — BŁĄD gh (dostęp/repo?)"; fi
}
set_var() {
  local n="$1" val="${2:-}"
  [ -n "$val" ] || { echo "  variable $n — pominięto (PUSTE w $ENVFILE)"; return; }
  if gh variable set "$n" -R "$REPO" --body "$val" >/dev/null 2>&1; then
    echo "  variable $n ✓"
  else echo "  variable $n — BŁĄD gh (dostęp/repo?)"; fi
}

# SSH key: expand a leading ~; optionally generate an ed25519 keypair if missing.
keyfile="${VAL_SSH_KEY_FILE:-}"; keyfile="${keyfile/#\~/$HOME}"
if [ -n "$keyfile" ] && [ ! -f "$keyfile" ] && [ "$GEN_KEY" -eq 1 ]; then
  echo ">> $keyfile brak — generuję parę ed25519 …"
  mkdir -p "$(dirname "$keyfile")"
  ssh-keygen -t ed25519 -N '' -C "deploy" -f "$keyfile"
  echo "  ┌─ DODAJ TEN KLUCZ PUBLICZNY do ${VAL_SSH_USER:-deploy}@${VAL_SSH_HOST:-host}:~/.ssh/authorized_keys ─┐"
  cat "$keyfile.pub"
  echo "  └────────────────────────────────────────────────────────────────────────────┘"
fi

echo "==> Secrets"
set_secret GPR_USER     "${VAL_GPR_USER:-}"
set_secret GPR_KEY      "${VAL_GPR_KEY:-}"
set_secret NPM_GH_TOKEN "${VAL_NPM_GH_TOKEN:-}"
set_secret SSH_HOST     "${VAL_SSH_HOST:-}"
set_secret SSH_USER     "${VAL_SSH_USER:-}"

if [ -n "$keyfile" ] && [ -f "$keyfile" ]; then
  if gh secret set SSH_KEY -R "$REPO" < "$keyfile" >/dev/null 2>&1; then echo "  secret   SSH_KEY ✓ (z pliku)"; else echo "  secret   SSH_KEY — BŁĄD gh"; fi
else
  echo "  secret   SSH_KEY — pominięto (ustaw SSH_KEY_FILE na istniejący klucz prywatny; --gen-key wygeneruje)"
fi

# SSH_KNOWN_HOSTS pinned from the host itself (no blind SSH in the deploy).
if [ -n "${VAL_SSH_HOST:-}" ]; then
  known="$(ssh-keyscan -t ed25519,rsa "${VAL_SSH_HOST}" 2>/dev/null || true)"
  if [ -n "$known" ]; then
    if printf '%s\n' "$known" | gh secret set SSH_KNOWN_HOSTS -R "$REPO" >/dev/null 2>&1; then echo "  secret   SSH_KNOWN_HOSTS ✓ (ssh-keyscan)"; else echo "  secret   SSH_KNOWN_HOSTS — BŁĄD gh"; fi
  else
    echo "  secret   SSH_KNOWN_HOSTS — pominięto (ssh-keyscan nic nie zwrócił dla $VAL_SSH_HOST)"
  fi
else
  echo "  secret   SSH_KNOWN_HOSTS — pominięto (brak SSH_HOST)"
fi

echo "==> Variables"
set_var GHCR_OWNER  "${VAL_GHCR_OWNER:-}"
set_var DEPLOY_PATH "${VAL_DEPLOY_PATH:-}"

if [ "$WITH_RELEASE" -eq 1 ]; then
  echo "==> Branch 'release' + protection"
  if git ls-remote --exit-code --heads origin release >/dev/null 2>&1; then
    echo "  branch release już istnieje na origin — pomijam."
  else
    git switch -c release && git push -u origin release && git switch -
  fi
  if gh api -X PUT "repos/$REPO/branches/release/protection" --input - >/dev/null 2>&1 <<'JSON'
{ "required_status_checks": null, "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 1 }, "restrictions": null }
JSON
  then echo "  protection ustawiona (PR + 1 review); wymagane statusy CI dodaj w UI."
  else echo "  UWAGA: protection nie ustawiona automatycznie — ustaw w UI (Settings → Branches)."; fi
fi

echo
echo "Gotowe. Sprawdź:  gh secret list -R $REPO  ;  gh variable list -R $REPO"
