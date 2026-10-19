#!/usr/bin/env bash
# Devcontainer konsumenta (templates/devcontainer/, N-SHOW-11, incubating) nie jest nowym źródłem wersji: JDK Gradle'a =
# kryteria demona obu starterów (= domyślne `java-version` z backend-ci.yml), JDK toolchainu = `java` katalogu,
# Node = frontend/.nvmrc. Token GitHub Packages nigdy nie trafia do obrazu ani do pliku: devcontainer.json przekazuje go
# przez remoteEnv z localEnv, a post-create.sh bez tokena niczego nie pobiera. Wzorzec: templates/tests/devcontainer.test.sh
# (devcontainer samej Platform), którego ten test nie zastępuje.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
template="$root/templates/devcontainer"
dockerfile="$template/Dockerfile"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
arg() { sed -n -E "s/^ARG $1=([^[:space:]]+)\$/\\1/p" "$dockerfile"; }
same() { [[ -n "$2" && "$2" == "$3" ]] || fail "$1 is '$2' but must equal $4 ('$3')"; }

for file in Dockerfile devcontainer.json post-create.sh README.md; do
  [[ -f "$template/$file" ]] || fail "templates/devcontainer/$file is missing"
done

catalog_java=$(sed -n -E 's/^java *= *"([0-9]+)".*/\1/p' "$root/gradle/catalog/libs.versions.toml")
gradle_jdk_ci=$(awk '/^      java-version:/ { inside = 1; next } inside && /default:/ { gsub(/[" ]/, "", $2); print $2; exit }' "$root/.github/workflows/backend-ci.yml")
node_major=$(tr -d '[:space:]' < "$root/frontend/.nvmrc")
for starter in java-library spring-app; do
  criteria=$(sed -n 's/^toolchainVersion=//p' "$root/templates/jvm/$starter/gradle/gradle-daemon-jvm.properties")
  same GRADLE_JDK "$(arg GRADLE_JDK)" "$criteria" "toolchainVersion of templates/jvm/$starter/gradle/gradle-daemon-jvm.properties"
done
same GRADLE_JDK "$(arg GRADLE_JDK)" "$gradle_jdk_ci" 'the java-version default of backend-ci.yml'
same TOOLCHAIN_JDK "$(arg TOOLCHAIN_JDK)" "$catalog_java" 'the java of gradle/catalog/libs.versions.toml'
same NODE_MAJOR "$(arg NODE_MAJOR)" "$node_major" 'frontend/.nvmrc'

grep -qE '^FROM [^ ]+:[^ @]+@sha256:[0-9a-f]{64}$' "$dockerfile" || fail 'the base image must be pinned by digest, keeping the tag'
gradle_home="ENV JAVA_HOME=/opt/jdk-\${GRADLE_JDK}"
toolchain_home="ENV TOOLCHAIN_JAVA_HOME=/opt/jdk-\${TOOLCHAIN_JDK}"
jdk_directory="mkdir -p \"/opt/jdk-\$version\""
grep -qxF "$gradle_home" "$dockerfile" || fail "JAVA_HOME must point at the JDK that runs Gradle ($gradle_home)"
grep -qxF "$toolchain_home" "$dockerfile" || fail "post-create.sh registers TOOLCHAIN_JAVA_HOME, so the Dockerfile must set it ($toolchain_home)"
grep -qF "$jdk_directory" "$dockerfile" || fail 'the Dockerfile must install each JDK where JAVA_HOME and TOOLCHAIN_JAVA_HOME point'

# Poświadczenia: ani w obrazie (ARG/ENV/build.args), ani w metadanych kontenera (containerEnv), ani w żadnym pliku szablonu.
if grep -iEq '^(ARG|ENV)[[:space:]]+[A-Z_]*(TOKEN|ACTOR|PASSWORD|SECRET|GPR)' "$dockerfile"; then
  fail 'the Dockerfile must not take a credential as ARG or ENV: it would end up in the image'
fi
leaked=$(grep -rlE '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})' "$template" || true)
[[ -z "$leaked" ]] || fail "a GitHub token literal is in: $leaked"
python3 - "$template/devcontainer.json" << 'PY' || fail 'devcontainer.json must pass the credentials through remoteEnv from localEnv only'
import json
import sys

config = json.load(open(sys.argv[1], encoding="utf-8"))
environment = config.get("remoteEnv", {})
for name in ("GITHUB_ACTOR", "GITHUB_TOKEN"):
    assert environment.get(name) == "${localEnv:%s}" % name, name
assert all(value.startswith("${localEnv:") for value in environment.values()), environment
assert "containerEnv" not in config, "containerEnv is stored in the container metadata"
assert "args" not in config.get("build", {}), "build args end up in the image history"
assert config.get("postCreateCommand") == "bash .devcontainer/post-create.sh", config.get("postCreateCommand")
PY

# post-create.sh w piaskownicy: atrapa npm zapisuje wywołania, HOME i repozytorium są tymczasowe.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/npm" << 'NPM'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >> "$NPM_LOG"
NPM
chmod +x "$tmp/bin/npm"
toolchain_home_path="/opt/jdk-$(arg TOOLCHAIN_JDK)"
secret='sentinel-token-value'
run_post_create() { # <sandbox> <lockfile: yes|no> <GITHUB_TOKEN>; wynik w $out, dziennik npm w $npm_log
  local repo="$tmp/$1/repo" home="$tmp/$1/home"
  mkdir -p "$repo/.devcontainer" "$repo/frontend" "$home"
  cp "$template/post-create.sh" "$repo/.devcontainer/post-create.sh"
  if [[ "$2" == yes ]]; then : > "$repo/frontend/package-lock.json"; fi
  npm_log="$tmp/$1/npm.log"
  out=$(cd "$repo" && HOME="$home" PATH="$tmp/bin:$PATH" TOOLCHAIN_JAVA_HOME="$toolchain_home_path" GITHUB_TOKEN="$3" NPM_LOG="$npm_log" \
    bash .devcontainer/post-create.sh 2>&1) || fail "post-create.sh failed ($1): $out"
  properties="$home/.gradle/gradle.properties"
  [[ "$(grep -c '^org.gradle.java.installations.paths=' "$properties")" -eq 1 ]] || fail "the toolchain JDK must be registered once ($1)"
  grep -qxF "org.gradle.java.installations.paths=$toolchain_home_path" "$properties" || fail "the toolchain JDK must be registered for Gradle ($1)"
  if grep -qF "$3" "$properties" "$repo/.devcontainer/post-create.sh" && [[ -n "$3" ]]; then fail "the token must not be written to a file ($1)"; fi
}

run_post_create no-token yes ''
[[ ! -e "$npm_log" ]] || fail 'without a token nothing may run that needs credentials'
grep -qF 'GITHUB_TOKEN is not set' <<< "$out" || fail "without a token the script must print a hint: $out"
grep -qF 'GITHUB_ACTOR' <<< "$out" || fail 'the hint must name GITHUB_ACTOR as well'

run_post_create with-token yes "$secret"
grep -qE '/frontend\|ci --ignore-scripts$' "$npm_log" || fail "npm ci --ignore-scripts must run in frontend/: $(cat "$npm_log")"
[[ "$(wc -l < "$npm_log")" -eq 1 ]] || fail 'npm must run exactly once'
if grep -qF "$secret" <<< "$out"; then fail 'the token must not be printed'; fi

run_post_create no-lockfile no "$secret"
[[ ! -e "$npm_log" ]] || fail 'without frontend/package-lock.json npm must not run (a backend-only repository)'

repo="$tmp/with-token/repo"
(cd "$repo" && HOME="$tmp/with-token/home" PATH="$tmp/bin:$PATH" TOOLCHAIN_JAVA_HOME="$toolchain_home_path" GITHUB_TOKEN="$secret" NPM_LOG="$npm_log" \
  bash .devcontainer/post-create.sh > /dev/null)
[[ "$(grep -c '^org.gradle.java.installations.paths=' "$tmp/with-token/home/.gradle/gradle.properties")" -eq 1 ]] \
  || fail 'a second run must not register the toolchain JDK again'

# Dokumentacja: status incubating i zmienne, których kontener oczekuje.
for document in "$dockerfile" "$template/README.md"; do
  grep -qi 'incubating' "$document" || fail "$document must say the template is incubating (Decision 7)"
done
for document in "$template/README.md" "$root/docs/consuming.md"; do
  grep -qF 'GITHUB_ACTOR' "$document" || fail "$document must name GITHUB_ACTOR"
  grep -qF 'GITHUB_TOKEN' "$document" || fail "$document must name GITHUB_TOKEN"
done
grep -qF '### Devcontainer (*incubating*)' "$root/docs/consuming.md" || fail 'docs/consuming.md needs a Devcontainer (incubating) section'

# Manifest: trzy pliki, opcjonalne, bo repozytorium bez devcontainera nie jest dryfem.
python3 - "$root/templates/manifest.json" << 'PY' || fail 'templates/manifest.json must list the three devcontainer files as optional copies'
import json
import sys

files = {entry["source"]: entry for entry in json.load(open(sys.argv[1], encoding="utf-8"))["files"]}
for name in ("Dockerfile", "devcontainer.json", "post-create.sh"):
    entry = files["devcontainer/" + name]
    assert entry["target"] == ".devcontainer/" + name, entry
    assert entry.get("optional") is True, entry
PY

echo "OK: the consumer devcontainer runs Gradle on Java $(arg GRADLE_JDK) with the Java $(arg TOOLCHAIN_JDK) toolchain and Node $(arg NODE_MAJOR); the token comes from the environment only"
