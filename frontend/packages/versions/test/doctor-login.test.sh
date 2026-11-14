#!/usr/bin/env bash
# platform-doctor PD032: ostrzeżenie, gdy build Gradle nie ma loginu GitHub (gpr.user / GITHUB_ACTOR), choć token jest.
# Pusta albo złożona z samych białych znaków wartość liczy się jak brak, jak w preflighcie starterów; bez budowy Gradle
# PD032 się nie pojawia. Tak samo PD030: pusty token (GPR_TOKEN, GITHUB_TOKEN, gpr.key) przechodzi do następnego źródła
# i bez innego daje FAIL, a token niepusty trafia do PD031 bez zmian. Atrapy java i curl, fałszywy HOME i wartości
# wyłącznie zmyślone: wartości nie trafiają na wyjście.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
fail() { echo "FAIL: $*" >&2; cat "$tmp/out" >&2; exit 1; }
: > "$tmp/out"

mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho "openjdk version \\"27.0.1\\" 2026-10-14" >&2\n' > "$tmp/bin/java"
cat > "$tmp/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_CURL_LOG"
printf '200'
STUB
chmod +x "$tmp/bin/java" "$tmp/bin/curl"
export FAKE_CURL_LOG="$tmp/curl.log"

# repo <nazwa> <backend|root|none>: backend = settings w backend/, root = settings w korzeniu, none = samo frontend/
repo() {
  local dir="$tmp/$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  case "$2" in
    backend)
      mkdir -p "$dir/backend"
      printf 'from("pl.seniordeveloper:platform-catalog:1.6.0")\n' > "$dir/backend/settings.gradle.kts"
      printf '#!/usr/bin/env bash\n' > "$dir/backend/gradlew" && chmod +x "$dir/backend/gradlew" ;;
    root)
      printf 'rootProject.name = "app"\n' > "$dir/settings.gradle.kts"
      printf 'platformVersion=1.6.0\n' > "$dir/gradle.properties"
      printf '#!/usr/bin/env bash\n' > "$dir/gradlew" && chmod +x "$dir/gradlew" ;;
    none)
      mkdir -p "$dir/frontend"
      printf '@dominiksienkiewicz:registry=https://npm.pkg.github.com\n' > "$dir/frontend/.npmrc"
      printf '{ "devDependencies": { "@dominiksienkiewicz/versions": "1.6.0" } }\n' > "$dir/frontend/package.json"
      echo '{}' > "$dir/frontend/package-lock.json" ;;
  esac
  printf '%s\n' "$dir"
}

# home <nazwa> [treść gradle.properties]: czysty HOME; bez drugiego argumentu nie ma ~/.gradle/gradle.properties
home() {
  local dir="$tmp/home-$1"
  mkdir -p "$dir"
  if [[ $# -gt 1 ]]; then mkdir -p "$dir/.gradle"; printf '%s\n' "$2" > "$dir/.gradle/gradle.properties"; fi
  printf '%s\n' "$dir"
}

# doctor <repo> <home> [ZMIENNA=wartość ...]: GITHUB_ACTOR i tokeny hosta nie przeciekają, ustawione są tylko podane.
doctor() {
  local dir=$1 fake_home=$2
  shift 2
  (cd "$dir" && env -u GITHUB_ACTOR -u GITHUB_TOKEN -u GPR_TOKEN HOME="$fake_home" PATH="$tmp/bin:$PATH" "$@" \
    bash "$here/../bin/platform-doctor.sh" --offline) > "$tmp/out" 2>&1
}

# doctor_online: jak doctor, ale bez --offline, więc PD031 woła atrapę curl z tokenem, który wybrał PD030.
doctor_online() {
  local dir=$1 fake_home=$2
  shift 2
  (cd "$dir" && env -u GITHUB_ACTOR -u GITHUB_TOKEN -u GPR_TOKEN HOME="$fake_home" PATH="$tmp/bin:$PATH" "$@" \
    bash "$here/../bin/platform-doctor.sh") > "$tmp/out" 2>&1
}

warn_line='WARN PD032 no GitHub login for Gradle (gpr.user / GITHUB_ACTOR)'
fix_line='fix: set gpr.user=<your GitHub login> in ~/.gradle/gradle.properties, or export GITHUB_ACTOR'
dummy_login=dummy-login-value
dummy_token=dummy-token-value

# Token jest, loginu nie ma (GITHUB_ACTOR nieustawiony): PD030 przechodzi, PD032 ostrzega z naprawą, a WARN nie psuje wyniku.
backend=$(repo backend backend)
doctor "$backend" "$(home empty)" GITHUB_TOKEN=$dummy_token || fail 'a missing login is a warning, not a failure'
grep -qF 'PASS PD030 credentials come from GITHUB_TOKEN' "$tmp/out" || fail 'the token must satisfy PD030 so the scenario is the real one'
grep -qF "$warn_line" "$tmp/out" || fail 'a token without a login must warn with PD032'
grep -qF "$fix_line" "$tmp/out" || fail 'the PD032 warning must name the fix'
if grep -q 'PASS PD032' "$tmp/out"; then fail 'a warned check must not also pass'; fi
if grep -qF "$dummy_token" "$tmp/out"; then fail 'the token value must never be printed'; fi

# Pusty GITHUB_ACTOR, jak go przekazuje devcontainer, gdy host nie ma zmiennej, i sam z białych znaków: brak loginu.
for blank in '' '   ' "$(printf '\t ')"; do
  doctor "$backend" "$(home empty)" GITHUB_TOKEN=$dummy_token "GITHUB_ACTOR=$blank" || fail 'a blank login is a warning, not a failure'
  grep -qF "$warn_line" "$tmp/out" || fail "GITHUB_ACTOR='$blank' must count as a missing login"
done

# Pusty gpr.user zasłania GITHUB_ACTOR tylko wtedy, gdy ten też jest pusty; tak samo działa filtr w settings.gradle.kts.
doctor "$backend" "$(home blank-user 'gpr.user=   ')" GITHUB_TOKEN=$dummy_token "GITHUB_ACTOR=" || fail 'a blank gpr.user is a warning'
grep -qF "$warn_line" "$tmp/out" || fail 'a blank gpr.user without GITHUB_ACTOR must count as a missing login'
doctor "$backend" "$(home blank-user 'gpr.user=   ')" GITHUB_TOKEN=$dummy_token "GITHUB_ACTOR=$dummy_login" || fail 'GITHUB_ACTOR must stand in for a blank gpr.user'
grep -qF 'PASS PD032 the GitHub login for Gradle comes from GITHUB_ACTOR' "$tmp/out" || fail 'a blank gpr.user must fall back to GITHUB_ACTOR'

# Wiersze, które nie są kluczem gpr.user: komentarz, inny klucz o wspólnym przedrostku, wartość w gpr.key.
properties=$(printf '#gpr.user=%s\ngpr.username=%s\ngpr.key=%s' "$dummy_login" "$dummy_login" "$dummy_token")
doctor "$backend" "$(home lookalike "$properties")" GITHUB_TOKEN=$dummy_token || fail 'lookalike keys are a warning, not a failure'
grep -qF "$warn_line" "$tmp/out" || fail 'a commented gpr.user, gpr.username or gpr.key must not count as a login'

# GITHUB_ACTOR ustawiony: PD032 przechodzi, nazywa źródło, nie drukuje wartości i nie dokłada ostrzeżenia.
doctor "$backend" "$(home empty)" GITHUB_TOKEN=$dummy_token "GITHUB_ACTOR=$dummy_login" || fail 'a login from GITHUB_ACTOR must pass'
grep -qF 'PASS PD032 the GitHub login for Gradle comes from GITHUB_ACTOR' "$tmp/out" || fail 'GITHUB_ACTOR must satisfy PD032'
if grep -qF 'WARN PD032' "$tmp/out"; then fail 'a login must not warn'; fi
if grep -qF "$dummy_login" "$tmp/out"; then fail 'the login value must not be printed'; fi

# gpr.user w ~/.gradle/gradle.properties, bez GITHUB_ACTOR: PD032 przechodzi i nazywa plik; ostatni wpis klucza wygrywa.
doctor "$backend" "$(home with-user "gpr.user=$dummy_login")" GITHUB_TOKEN=$dummy_token || fail 'a login from gpr.user must pass'
grep -qF 'PASS PD032 the GitHub login for Gradle comes from gpr.user in ~/.gradle/gradle.properties' "$tmp/out" || fail 'gpr.user must satisfy PD032'
if grep -qF 'WARN PD032' "$tmp/out"; then fail 'a login must not warn'; fi
if grep -qF "$dummy_login" "$tmp/out"; then fail 'the login value must not be printed'; fi
doctor "$backend" "$(home spaced-user "  gpr.user = $dummy_login")" GITHUB_TOKEN=$dummy_token || fail 'gpr.user with spaces around the separator must pass'
grep -qF 'PASS PD032' "$tmp/out" || fail 'Properties allows whitespace around the separator'
doctor "$backend" "$(home overridden "$(printf 'gpr.user=%s\ngpr.user=' "$dummy_login")")" GITHUB_TOKEN=$dummy_token || fail 'a later blank gpr.user is a warning'
grep -qF "$warn_line" "$tmp/out" || fail 'the last gpr.user entry wins, as in java.util.Properties'

# Settings w korzeniu repozytorium to też build Gradle.
root=$(repo root root)
doctor "$root" "$(home empty)" GITHUB_TOKEN=$dummy_token || fail 'a root settings.gradle.kts without a login is a warning'
grep -qF "$warn_line" "$tmp/out" || fail 'a root settings.gradle.kts must run PD032'

# Bez builda Gradle (samo frontend/) PD032 się nie pojawia, także przy tokenie i braku loginu.
frontend=$(repo frontend none)
doctor "$frontend" "$(home empty)" GITHUB_TOKEN=$dummy_token || true
grep -qF 'PD020' "$tmp/out" || fail 'the doctor must have run on the frontend-only repository'
if grep -q 'PD032' "$tmp/out"; then fail 'PD032 must not run without a Gradle build'; fi

# PD030: pusty albo złożony z samych białych znaków token liczy się jak brak, jak w settings.gradle.kts. Bez innego źródła
# to FAIL z komunikatem o braku poświadczeń (PD031 nie dostaje nic do sprawdzenia), z innym źródłem PD030 przechodzi dalej.
missing_token='FAIL PD030 no GitHub Packages credentials (GPR_TOKEN, GITHUB_TOKEN or gpr.key)'
tab=$(printf '\t')
for blank_token in 'GPR_TOKEN=' 'GPR_TOKEN=   ' "GPR_TOKEN=$tab " 'GITHUB_TOKEN=' 'GITHUB_TOKEN=   ' "GITHUB_TOKEN=$tab"; do
  : > "$FAKE_CURL_LOG"
  if doctor_online "$backend" "$(home empty)" "GITHUB_ACTOR=$dummy_login" "$blank_token"; then fail "$blank_token as the only token source must fail PD030"; fi
  grep -qF "$missing_token" "$tmp/out" || fail "$blank_token must count as a missing token"
  if grep -q 'PASS PD030' "$tmp/out"; then fail "$blank_token must not pass PD030"; fi
  [[ ! -s "$FAKE_CURL_LOG" ]] || fail "$blank_token must not reach GitHub Packages as a credential"
done
for blank_key in 'gpr.key=' 'gpr.key=   ' "gpr.key=$tab"; do
  if doctor "$backend" "$(home blank-key "$blank_key")" "GITHUB_ACTOR=$dummy_login"; then fail "'$blank_key' as the only token source must fail PD030"; fi
  grep -qF "$missing_token" "$tmp/out" || fail "'$blank_key' in gradle.properties must count as a missing token"
done

# Pusty token przepuszcza do następnego źródła w kolejności GPR_TOKEN, GITHUB_TOKEN, gpr.key.
doctor "$backend" "$(home empty)" "GITHUB_ACTOR=$dummy_login" 'GPR_TOKEN=   ' "GITHUB_TOKEN=$dummy_token" || fail 'a blank GPR_TOKEN must fall through to GITHUB_TOKEN'
grep -qF 'PASS PD030 credentials come from GITHUB_TOKEN' "$tmp/out" || fail 'a blank GPR_TOKEN must fall through to a valid GITHUB_TOKEN'
doctor "$backend" "$(home valid-key "gpr.key=$dummy_token")" "GITHUB_ACTOR=$dummy_login" 'GPR_TOKEN=   ' "GITHUB_TOKEN=$tab" \
  || fail 'blank environment tokens must fall through to gpr.key'
grep -qF 'PASS PD030 credentials come from gpr.key in ~/.gradle/gradle.properties' "$tmp/out" || fail 'blank environment tokens must fall through to a valid gpr.key'
doctor "$backend" "$(home empty)" "GITHUB_ACTOR=$dummy_login" "GPR_TOKEN=$dummy_token" "GITHUB_TOKEN=$dummy_token-other" || fail 'two valid tokens must pass'
grep -qF 'PASS PD030 credentials come from GPR_TOKEN' "$tmp/out" || fail 'a valid GPR_TOKEN must keep precedence over GITHUB_TOKEN'

# Token niepusty dociera do PD031 bez zmian, także po przejściu z pustego źródła (login z GITHUB_ACTOR, jak w curl -u).
: > "$FAKE_CURL_LOG"
doctor_online "$backend" "$(home empty)" "GITHUB_ACTOR=$dummy_login" 'GPR_TOKEN=   ' "GITHUB_TOKEN=$dummy_token" || fail 'a token reached through a blank source must pass PD031'
grep -qF 'PASS PD031 the catalog 1.6.0 resolves from GitHub Packages' "$tmp/out" || fail 'PD031 must run with the token PD030 chose'
grep -qF -- "-u $dummy_login:$dummy_token " "$FAKE_CURL_LOG" || fail 'PD031 must send the token PD030 chose, unchanged'
if grep -qF "$dummy_token" "$tmp/out"; then fail 'the token value must never be printed'; fi
: > "$FAKE_CURL_LOG"
doctor_online "$backend" "$(home valid-key "gpr.key=$dummy_token")" "GITHUB_ACTOR=$dummy_login" || fail 'gpr.key must pass PD031'
grep -qF -- "-u $dummy_login:$dummy_token " "$FAKE_CURL_LOG" || fail 'PD031 must send the gpr.key token unchanged'

echo 'OK: platform-doctor PD032 warns when a Gradle build has a token but no GitHub login, says nothing without Gradle, and PD030 counts a blank token as missing'
