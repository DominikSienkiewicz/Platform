#!/usr/bin/env bash
# setup-gh-deploy.sh — push the GitHub Actions secrets + variables that the reusable
# deploy workflow (DominikSienkiewicz/Platform/.github/workflows/deploy.yml@v1) needs,
# from a LOCAL git-ignored file. Secret VALUES never pass through an agent and are never
# echoed — you fill `.secrets.local` and run this yourself. Inside a git work tree the script
# refuses to run unless `git check-ignore` confirms that the file is ignored.
#
# CANON: this file lives in Platform/templates/setup-gh-deploy.sh — do not edit per-repo
# copies; edit here and re-sync to each consumer's scripts/ (see templates/README.md).
#
# Contract pushed (must match the reusable deploy.yml):
#   repository secrets:  GPR_USER GPR_KEY NPM_GH_TOKEN
#   environment `production` (deployment branch `release` only) with its secrets:
#                        SSH_HOST SSH_USER SSH_KEY SSH_KNOWN_HOSTS
#   variables:           GHCR_OWNER DEPLOY_PATH
# Only a job that runs in `production`, and so only a workflow run from `release`, can read the SSH
# secrets. Repository-level SSH_* secrets left from an older bootstrap are reported with the command
# that deletes them. Environment secrets in a private repository need GitHub Pro, Team or Enterprise.
# SSH_KEY is read from a file (SSH_KEY_FILE); SSH_KNOWN_HOSTS is generated with ssh-keyscan and,
# when SSH_HOST_KEY_SHA256 is set, verified against that fingerprint before anything is pushed.
# Exits non-zero when any gh call fails, so a partial bootstrap never ends in "Gotowe".
# GITHUB_TOKEN is provided automatically by Actions — not bootstrapped here.
#
# Usage:
#   cp .secrets.local.example .secrets.local   # then fill in real values
#   ./scripts/setup-gh-deploy.sh
#   ./scripts/setup-gh-deploy.sh --gen-key       # generate an ed25519 deploy key if missing
#   ./scripts/setup-gh-deploy.sh --with-release  # also create branch `release`: PR required, no approval
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

# `git add -A` must never pick up the PATs. A file outside every work tree cannot be committed,
# so the guard applies only when ENVFILE lies inside one.
ENVDIR="$(cd "$(dirname "$ENVFILE")" && pwd -P)"
if [ "$(git -C "$ENVDIR" rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
  && ! git -C "$ENVDIR" check-ignore -q -- "$(basename "$ENVFILE")"; then
  cat >&2 <<EOF
BŁĄD: git nie ignoruje $ENVFILE — \`git add -A\` wciągnąłby PAT-y do historii.
  - dodaj regułę '.secrets.local' do .gitignore (kanon: Platform/templates/gitignore/root.gitignore)
  - sprawdź:             git check-ignore -v "$ENVFILE"
  - plik już śledzony?   git rm --cached "$ENVFILE", potem zrotuj tokeny
EOF
  exit 1
fi

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

failures=0

# ssh-keyscan alone trusts whatever key answers on the network path at bootstrap. With a fingerprint
# from a trusted channel (the host's console, or ssh-keygen -lf on the box) a mismatch stops the script.
verify_host_key() {
  local known="$1" expected="${VAL_SSH_HOST_KEY_SHA256:-}" fingerprints
  if [ -z "$expected" ]; then
    echo "WARNING: SSH_HOST_KEY_SHA256 is empty, so SSH_KNOWN_HOSTS trusts whatever key answered ssh-keyscan (trust on first use)." >&2
    return 0
  fi
  expected="SHA256:${expected#SHA256:}"
  fingerprints="$(ssh-keygen -lf - <<<"$known" 2>/dev/null | awk '{ print $2 }' || true)"
  if grep -qxF -- "$expected" <<<"$fingerprints"; then
    echo "Host key of $VAL_SSH_HOST matches $expected."
    return 0
  fi
  echo "ERROR: no key of $VAL_SSH_HOST matches SSH_HOST_KEY_SHA256 ($expected); ssh-keyscan returned: ${fingerprints:-nothing}. Nothing was pushed." >&2
  return 1
}

known=""
if [ -n "${VAL_SSH_HOST:-}" ]; then
  known="$(ssh-keyscan -t ed25519,rsa "${VAL_SSH_HOST}" 2>/dev/null || true)"
  if [ -n "$known" ]; then verify_host_key "$known" || exit 1; fi
fi

set_secret() { # name value — value via stdin, never on the command line
  local n="$1" val="${2:-}"
  [ -n "$val" ] || { echo "  secret   $n — pominięto (PUSTE w $ENVFILE)"; return; }
  if printf '%s' "$val" | gh secret set "$n" -R "$REPO" >/dev/null 2>&1; then
    echo "  secret   $n ✓"
  else echo "  secret   $n — BŁĄD gh (dostęp/repo?)"; failures=$((failures + 1)); fi
}
set_env_secret() { # name value — a secret of the production environment, value via stdin
  local n="$1" val="${2:-}"
  if [ "$ENV_READY" -ne 1 ]; then echo "  secret   $n — skipped (environment production is missing)"; return; fi
  [ -n "$val" ] || { echo "  secret   $n — pominięto (PUSTE w $ENVFILE)"; return; }
  if printf '%s' "$val" | gh secret set "$n" -R "$REPO" --env production >/dev/null 2>&1; then
    echo "  secret   $n ✓ (environment production)"
  else echo "  secret   $n — BŁĄD gh (dostęp/repo?)"; failures=$((failures + 1)); fi
}
set_var() {
  local n="$1" val="${2:-}"
  [ -n "$val" ] || { echo "  variable $n — pominięto (PUSTE w $ENVFILE)"; return; }
  if gh variable set "$n" -R "$REPO" --body "$val" >/dev/null 2>&1; then
    echo "  variable $n ✓"
  else echo "  variable $n — BŁĄD gh (dostęp/repo?)"; failures=$((failures + 1)); fi
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

# The deploy job runs in `production`; a deployment branch policy limits it to `release`, so a workflow
# on any other branch can neither deploy nor read the SSH secrets below.
echo "==> Environment production (deployment branch: release)"
ENV_READY=0
if gh api -X PUT "repos/$REPO/environments/production" --input - >/dev/null 2>&1 <<'JSON'
{ "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
then
  ENV_READY=1
  echo "  environment production ✓"
  if gh api "repos/$REPO/environments/production/deployment-branch-policies" --jq '.branch_policies[].name' 2>/dev/null | grep -qx release; then
    echo "  branch policy release — already set"
  elif gh api -X POST "repos/$REPO/environments/production/deployment-branch-policies" -f name=release -f type=branch >/dev/null 2>&1; then
    echo "  branch policy release ✓"
  else
    echo "  branch policy release — BŁĄD gh"; failures=$((failures + 1))
  fi
else
  echo "  environment production — BŁĄD gh (admin on the repo? a private repo needs GitHub Pro, Team or Enterprise)"
  failures=$((failures + 1))
fi

set_env_secret SSH_HOST "${VAL_SSH_HOST:-}"
set_env_secret SSH_USER "${VAL_SSH_USER:-}"

if [ "$ENV_READY" -ne 1 ]; then
  echo "  secret   SSH_KEY — skipped (environment production is missing)"
elif [ -n "$keyfile" ] && [ -f "$keyfile" ]; then
  if gh secret set SSH_KEY -R "$REPO" --env production < "$keyfile" >/dev/null 2>&1; then echo "  secret   SSH_KEY ✓ (z pliku, environment production)"; else echo "  secret   SSH_KEY — BŁĄD gh"; failures=$((failures + 1)); fi
else
  echo "  secret   SSH_KEY — pominięto (ustaw SSH_KEY_FILE na istniejący klucz prywatny; --gen-key wygeneruje)"
fi

# SSH_KNOWN_HOSTS pinned from the host itself (no blind SSH in the deploy), verified above.
if [ "$ENV_READY" -ne 1 ]; then
  echo "  secret   SSH_KNOWN_HOSTS — skipped (environment production is missing)"
elif [ -n "${VAL_SSH_HOST:-}" ]; then
  if [ -n "$known" ]; then
    if printf '%s\n' "$known" | gh secret set SSH_KNOWN_HOSTS -R "$REPO" --env production >/dev/null 2>&1; then echo "  secret   SSH_KNOWN_HOSTS ✓ (ssh-keyscan, environment production)"; else echo "  secret   SSH_KNOWN_HOSTS — BŁĄD gh"; failures=$((failures + 1)); fi
  else
    echo "  secret   SSH_KNOWN_HOSTS — pominięto (ssh-keyscan nic nie zwrócił dla $VAL_SSH_HOST)"
  fi
else
  echo "  secret   SSH_KNOWN_HOSTS — pominięto (brak SSH_HOST)"
fi

# Repository-level copies from an older bootstrap stay readable from every branch until deleted.
leftover="$(gh secret list -R "$REPO" --json name --jq '.[].name' 2>/dev/null | grep -xE 'SSH_(HOST|USER|KEY|KNOWN_HOSTS)' || true)"
if [ -n "$leftover" ]; then
  echo "WARNING: repository-level secrets $(tr '\n' ' ' <<<"$leftover")are readable from any branch. The deploy reads the environment copies; delete these:" >&2
  while IFS= read -r n; do echo "  gh secret delete $n -R $REPO" >&2; done <<<"$leftover"
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
  "required_pull_request_reviews": { "required_approving_review_count": 0 }, "restrictions": null }
JSON
  then echo "  protection set: a pull request is required, no approval (one maintainer can merge); add required CI checks in the UI."
  else echo "  UWAGA: protection nie ustawiona automatycznie — ustaw w UI (Settings → Branches)."; fi
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "ERROR: $failures gh call(s) failed; the secrets and variables above marked BŁĄD are not set or are stale." >&2
  exit 1
fi
echo "Gotowe. Sprawdź:  gh secret list -R $REPO  ;  gh variable list -R $REPO"
