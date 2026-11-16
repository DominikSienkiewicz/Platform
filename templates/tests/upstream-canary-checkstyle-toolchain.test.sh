#!/usr/bin/env bash
# Noga next-jdk w upstream-canary.yml uruchamia Checkstyle na toolchainie kanonu, a resztę startera na następnym JDK.
#
# Kontekst (bug): JDK 28-ea+24 domyślnie odrzuca dwuargumentowe ReflectionFactory.newConstructorForSerialization,
# a Gradle (9.8.2, także 9.9.1) odtwarza nim WorkParameters w workerze procesowym — gradle/gradle#39837. Checkstyle
# biegnie w takim workerze na toolchainie projektu, więc przebieg 43875663032 padł na checkstyleMain i checkstyleTest
# ("Run with -Djdk.reflect.allowNonSerializableConstruction=true"), choć Platform niczego nie zmieniła. Flagi nie da
# się podać: task Checkstyle nie ma jvmArgs, a worker procesowy dostaje z env tylko LANG/LANGUAGE/LC_*
# (DefaultProcessWorkerSpec), więc JAVA_TOOL_OPTIONS do niego nie dociera. Checkstyle czyta źródła, nie bajtkod,
# więc JVM jego workera nie zmienia tego, co noga mierzy.
#
# Test wycina z YAML-a prawdziwe bloki (sentinele `# >>> next-jdk-*` / `# <<< next-jdk-*`), uruchamia je na katalogu
# tego repo i na stubie gradlew, a w init scripcie sprawdza zakres (tylko Checkstyle) i warunek zdjęcia.
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
yaml="$root/.github/workflows/upstream-canary.yml"
init="$root/.github/upstream-canary/checkstyle-on-canon-toolchain.init.gradle.kts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

extract() { awk -v start="# >>> $1" -v end="# <<< $1" 'index($0, start){f=1;next} index($0, end){f=0} f' "$yaml"; }

[ -f "$init" ] \
  || fail 'the next-JDK leg must run Checkstyle on the canon toolchain (gradle/gradle#39837), but .github/upstream-canary/checkstyle-on-canon-toolchain.init.gradle.kts is missing'

canon=$(sed -n -E 's/^java *= *"([0-9]+)".*/\1/p' "$root/gradle/catalog/libs.versions.toml")
[ -n "$canon" ] || fail 'gradle/catalog/libs.versions.toml has no java version'

extract next-jdk-versions > "$tmp/versions.sh"
[ -s "$tmp/versions.sh" ] || fail 'upstream-canary.yml has no next-jdk-versions block'
(cd "$root" && GITHUB_OUTPUT="$tmp/versions.out" bash "$tmp/versions.sh") || fail 'the next-jdk-versions block failed'
[ "$(sed -n 's/^canon=//p' "$tmp/versions.out")" = "$canon" ] \
  || fail "the next-JDK leg must name the canon toolchain $canon for Checkstyle, named: '$(sed -n 's/^canon=//p' "$tmp/versions.out")'"
[ "$(sed -n 's/^version=//p' "$tmp/versions.out")" = "$((canon + 1))" ] \
  || fail "the next-JDK leg must still build on Java $((canon + 1))"

extract next-jdk-starter-build > "$tmp/build.sh"
[ -s "$tmp/build.sh" ] || fail 'upstream-canary.yml has no next-jdk-starter-build block'
workspace="$tmp/workspace"
mkdir -p "$workspace/templates/jvm/java-library"
cat > "$workspace/templates/jvm/java-library/gradlew" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GRADLEW_ARGS"
STUB
chmod +x "$workspace/templates/jvm/java-library/gradlew"
(
  cd "$workspace" \
    && GITHUB_WORKSPACE="$root" RUNNER_TEMP="$tmp/runner" repo="$tmp/runner/platform-repo" NEXT=$((canon + 1)) \
      CANON="$canon" BUILD_LOG="$tmp/build.log" GRADLEW_ARGS="$tmp/args" bash -c 'mkdir -p "$RUNNER_TEMP" && . "$0"' "$tmp/build.sh"
) || fail 'the next-jdk-starter-build block failed on the stub'
[ -s "$tmp/args" ] || fail 'the next-jdk-starter-build block must run the starter wrapper'

has_arg() { grep -qxF -- "$1" "$tmp/args"; }
has_arg build || fail 'the starter must still run the build task'
has_arg "-Pplatform.toolchain.override=$((canon + 1))" || fail 'the starter must still build on the next toolchain'
grep -A1 -xF -- '--init-script' "$tmp/args" | tail -1 | grep -qxF -- "$init" \
  || fail "the starter build must apply $init"
has_arg "-PcanaryCheckstyleJava=$canon" || fail "the starter build must pass the canon toolchain $canon to the init script"

grep -q 'canaryCheckstyleJava' "$init" || fail 'the init script must read the canon toolchain from -PcanaryCheckstyleJava'
grep -q 'withType<Checkstyle>' "$init" || fail 'the init script must configure the Checkstyle tasks'
others=$(grep -oE 'withType<[A-Za-z]+>' "$init" | grep -v 'withType<Checkstyle>' || true)
[ -z "$others" ] || fail "the init script must leave every other task on the next toolchain, configures: $others"
grep -q 'gradle/gradle#39837' "$init" || fail 'the init script must name gradle/gradle#39837 as the condition for its removal'

echo 'OK: the next-JDK canary runs Checkstyle on the canon toolchain and the rest of the starter on the next JDK'
