#!/usr/bin/env bash
# platform-bump jest transakcyjny: preflight zatrzymuje go przed pierwszym zapisem (kod 2), błąd po zapisie
# przywraca każdy plik, a --dry-run pokazuje zmiany bez zapisu. Cały bin na atrapach (bump-fixture.sh).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$(dirname "$0")/bump-fixture.sh"

# (a) cudze niezacommitowane zmiany w pliku, który bump przepisuje: kod 2, plik nietknięty
dir=$(consumer dirty)
printf '{ "devDependencies": { "@dominiksienkiewicz/versions": "1.5.29", "react": "19.1.0" } }\n' > "$dir/frontend/package.json"
cp "$dir/frontend/package.json" "$fixture_work/dirty.json"
bump "$dir" 9.9.9
[[ $rc -eq 2 ]] || { cat "$dir.log"; fail "(a) a dirty tree must exit 2, got $rc"; }
grep -qF 'Uncommitted changes in files platform-bump rewrites' "$dir.log" || { cat "$dir.log"; fail '(a) the refusal must say why'; }
grep -qF 'frontend/package.json' "$dir.log" || fail '(a) the refusal must list the dirty file'
cmp -s "$dir/frontend/package.json" "$fixture_work/dirty.json" || fail '(a) the dirty file must stay byte-identical'
bump "$dir" --allow-dirty 9.9.9
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail '(a) --allow-dirty must let the bump run'; }

# (b) npm pack pada PO przepisaniu pinów: rollback do stanu z commita, bajt w bajt
dir=$(consumer rollback)
FAKE_PACK=E401 bump "$dir" 9.9.9
[[ $rc -ne 0 ]] || { cat "$dir.log"; fail '(b) a failing npm pack must fail the bump'; }
grep -qF 'restored every file it had changed' "$dir.log" || { cat "$dir.log"; fail '(b) the rollback must be reported'; }
[[ -z "$(git -C "$dir" status --porcelain)" ]] || { git -C "$dir" status --porcelain; fail '(b) the rollback must leave the tree as committed'; }

# (c) --dry-run: zmienione linie na wyjściu, zero zapisów, bez npm install
dir=$(consumer dry-run)
: > "$FAKE_NPM_LOG"
bump "$dir" --dry-run 9.9.9
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail '(c) a dry run must succeed'; }
grep -qF -- '-    "@dominiksienkiewicz/versions": "1.5.29",' "$dir.log" || { cat "$dir.log"; fail '(c) the old pin must be shown'; }
grep -qF -- '+    "@dominiksienkiewicz/versions": "9.9.9",' "$dir.log" || fail '(c) the new pin must be shown'
grep -qF -- '+    "react": "19.2.8"' "$dir.log" || fail '(c) the canon change must be shown'
grep -qF -- '+    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v9.9.9' "$dir.log" || fail '(c) the workflow ref must be shown'
[[ -z "$(git -C "$dir" status --porcelain)" ]] || { git -C "$dir" status --porcelain; fail '(c) a dry run must not change the tree'; }
if grep -q '^npm install' "$FAKE_NPM_LOG"; then fail '(c) a dry run must not run npm install'; fi

# (d) zły token: 401 i brak zakresu read:packages zatrzymują bump przed zapisem
dir=$(consumer token)
FAKE_USER_CODE=401 bump "$dir" 9.9.9
[[ $rc -eq 2 ]] || { cat "$dir.log"; fail "(d) a rejected token must exit 2, got $rc"; }
grep -qF 'GitHub rejected the token (401)' "$dir.log" || fail '(d) the 401 must be named'
FAKE_USER_CODE=200 FAKE_SCOPES='repo, workflow' bump "$dir" 9.9.9
[[ $rc -eq 2 ]] || { cat "$dir.log"; fail '(d) a token without read:packages must exit 2'; }
grep -qF 'lacks the read:packages scope' "$dir.log" || fail '(d) the missing scope must be named'
FAKE_USER_CODE=200 FAKE_SCOPES='repo, read:packages' bump "$dir" --dry-run 9.9.9
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail '(d) a classic PAT with read:packages must pass'; }
FAKE_USER_CODE=403 bump "$dir" --dry-run 9.9.9
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail '(d) a token GitHub does not describe (Actions, fine-grained) must only warn'; }
[[ -z "$(git -C "$dir" status --porcelain)" ]] || fail '(d) none of the token cases may change the tree'

# (e) brak narzędzia: backend bez wykonywalnego gradlew to kod 2 przed zapisem
dir=$(consumer tools)
mkdir -p "$dir/backend"
printf 'plugins { id("seniordev.settings-conventions") version "1.5.29" }\n' > "$dir/backend/settings.gradle.kts"
printf '#!/usr/bin/env bash\n' > "$dir/backend/gradlew"
bump "$dir" 9.9.9
[[ $rc -eq 2 ]] || { cat "$dir.log"; fail "(e) a backend without an executable gradlew must exit 2, got $rc"; }
grep -qF 'needs an executable backend/gradlew' "$dir.log" || fail '(e) the missing tool must be named'

# (f) nieznana opcja i niepoprawna wersja
dir=$(consumer usage)
bump "$dir" --force
if [[ $rc -ne 2 ]] || ! grep -qF 'Unknown option --force' "$dir.log"; then cat "$dir.log"; fail '(f) an unknown option must exit 2'; fi
bump "$dir" v9.9.9
if [[ $rc -ne 2 ]] || ! grep -qF 'Expected one X.Y.Z version' "$dir.log"; then cat "$dir.log"; fail '(f) a malformed version must exit 2'; fi

echo 'OK: platform-bump refuses before writing, rolls back on failure and previews with --dry-run'
