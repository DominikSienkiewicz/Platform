#!/usr/bin/env bash
# Testuje aktualizację katalogu na atrapach Gradle i Maven Central.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cd "$fixture"
git init -q -b fixture
git config core.hooksPath /dev/null
mkdir -p scripts bin gradle/catalog gradle/build-logic/gradle gradle/test-fixtures/gradle \
  frontend/packages/versions/agents
cp "$here/agents-stack.py" "$here/write-verification-metadata.sh" scripts/
if [[ -f "$here/refresh-catalog-update.sh" ]]; then cp "$here/refresh-catalog-update.sh" scripts/; fi
cat > gradle/maven-modules.txt <<'EOF'
build-logic example.build-logic
catalog example.catalog
test-fixtures example.test-fixtures
EOF
catalog=gradle/catalog/libs.versions.toml
cat > "$catalog" <<'EOF'
[versions]
java = "27"
gradle = "9.8.2"
springBoot = "4.1.0"
springModulith = "2.1.1"
springAi = "2.0.2"
junit = "6.1.3"
tomcat = "11.0.29"
jooq = "3.21.6"  # lustro z BOM-u
lombok = "1.18.48"  # lustro z BOM-u
EOF
git add "$catalog"
git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgSign=false commit -qm base
base=$(git rev-parse HEAD)
export CALLS="$fixture/calls" PATH="$fixture/bin:$PATH"
cat > bin/curl <<'EOF'
#!/usr/bin/env bash
set -eu
echo "curl ${!#}" >> "$CALLS"
cat <<POM
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>org.springframework.boot</groupId><artifactId>spring-boot-dependencies</artifactId>
  <version>4.1.1</version><properties>
    <jooq.version>${FIXTURE_JOOQ:-3.21.7}</jooq.version><lombok.version>${FIXTURE_LOMBOK:-1.18.50}</lombok.version>
  </properties>
</project>
POM
EOF
cat > bin/gradlew <<'EOF'
#!/usr/bin/env bash
set -eu
echo "${PWD##*/} $*" >> "$CALLS"
if [[ "$1" == dependencies && -n "${UNRESOLVED:-}" ]]; then echo '\--- org.example:broken:1.0 FAILED'; fi
EOF
chmod +x bin/curl bin/gradlew
for module in build-logic test-fixtures; do
  cp bin/gradlew "gradle/$module/gradlew"
  touch "gradle/$module/gradle/verification-metadata.xml"
done
refresh() { bash scripts/refresh-catalog-update.sh "$base"; }
change_version() {
  sed "s/^$1 = \"$2\"/$1 = \"$3\"/" "$catalog" > candidate.toml
  mv candidate.toml "$catalog"
}

change_version springBoot 4.1.0 4.1.1
if [[ -f scripts/refresh-catalog-update.sh ]]; then refresh; fi
grep -qxF 'jooq = "3.21.7"  # lustro z BOM-u' "$catalog" || fail 'jOOQ must mirror the selected Boot BOM'
grep -qxF 'lombok = "1.18.50"  # lustro z BOM-u' "$catalog" || fail 'Lombok must mirror the selected Boot BOM'
grep -qxF 'curl https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-dependencies/4.1.1/spring-boot-dependencies-4.1.1.pom' "$CALLS" || fail 'the POM must come from the selected Boot release'
python3 scripts/agents-stack.py --check || fail 'the exported backend stack must match the new catalog'
for module in build-logic test-fixtures; do
  for task in build dependencies; do
    flags=$(grep "^$module $task " "$CALLS") || fail "missing $task for $module"
    for flag in '--write-locks' '--write-verification-metadata sha256' '--refresh-dependencies'; do
      [[ " $flags " == *" $flag "* ]] || fail "$module $task lacks $flag"
    done
  done
done
grep -q '^build-logic build -x test ' "$CALLS" || fail 'the metadata build of build-logic must exclude TestKit'

: > "$CALLS"
git show "$base:$catalog" > "$catalog"
refresh
[[ ! -s "$CALLS" ]] || fail 'an unchanged catalog must skip regeneration'
change_version tomcat 11.0.29 11.0.30
refresh
if grep -q '^curl ' "$CALLS"; then fail 'an independent Tomcat update must skip the Boot POM'; fi
grep -q '^test-fixtures dependencies ' "$CALLS" || fail 'an independent Tomcat update must regenerate locks'
if UNRESOLVED=1 refresh > output 2>&1; then fail 'an unresolved Gradle dependency must block the update'; fi
grep -qF 'org.example:broken:1.0 FAILED' output || fail 'the unresolved dependency must appear in the log'

change_version springBoot 4.1.0 4.1.1
if FIXTURE_JOOQ='unresolved' refresh > output 2>&1; then fail 'the Boot POM must contain an exact stable jOOQ version'; fi
grep -qxF 'jooq = "3.21.6"  # lustro z BOM-u' "$catalog" || fail 'an invalid POM must preserve the existing jOOQ pin'
if FIXTURE_LOMBOK='unresolved' refresh > output 2>&1; then fail 'the Boot POM must contain an exact stable Lombok version'; fi
grep -qxF 'jooq = "3.21.6"  # lustro z BOM-u' "$catalog" || fail 'an invalid Lombok must also preserve the jOOQ pin'
git show "$base:$catalog" > "$catalog"
change_version jooq 3.21.6 3.22.0
if refresh > output 2>&1; then fail 'a jOOQ update without a matching Boot update must fail'; fi
grep -qF 'jOOQ must follow' output || fail 'a standalone jOOQ update must explain the Boot requirement'
git show "$base:$catalog" > "$catalog"
change_version lombok 1.18.48 1.18.50
if refresh > output 2>&1; then fail 'a Lombok update without a matching Boot update must fail'; fi

: > "$CALLS"
bash scripts/write-verification-metadata.sh build-logic
if grep -Fq -- '--write-locks' "$CALLS"; then fail 'the existing metadata-only invocation must keep lockfiles unchanged'; fi
echo 'OK: a catalog update refreshes the Boot jOOQ and Lombok mirrors, agent stack, locks and verification metadata'
