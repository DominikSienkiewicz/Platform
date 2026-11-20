#!/usr/bin/env bash
# upstream-canary.yml, case by case: the next-JDK leg fails on bytecode a tool cannot read, and runs Checkstyle on the
# canon toolchain while the rest of the starter builds on the next JDK. Blocks cut out of the workflow run on logs and a
# stub gradlew. Shared helpers (fail, block) live in lib/workflow.sh.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=lib/workflow.sh
source "$(dirname "$0")/lib/workflow.sh"
# shellcheck disable=SC2034 # workflow czyta lib/workflow.sh
workflow="$root/.github/workflows/upstream-canary.yml"

# --- unread-bytecode ---
# Noga next-jdk w upstream-canary.yml failuje, gdy narzędzie nie czyta bajtkodu następnego toolchainu.
#
# Kontekst (bug): SpotBugs jest report-only (ADR-0005), więc na Javie 28 EA kończy się "SpotBugs ended with exit
# code 4", a build idzie dalej. Przebieg 40310414262 był czerwony tylko przez JaCoCo 0.8.15; po wydaniu JaCoCo
# z Javą 28 kanarek zrobiłby się zielony, choć SpotBugs nie przeanalizowałby ani jednej klasy. Warunek jest ten sam,
# co PlatformConsumerFunctionalTest.assertAnalyzersReadTheBytecode dla toolchainu kanonu: "Unsupported class file
# major version" w wyjściu buildu = czerwony krok, a nazwy narzędzi idą do issue.
#
# Test wycina prawdziwy blok z YAML-a (sentinele `# >>> scan-unread-bytecode` / `# <<< scan-unread-bytecode`)
# i uruchamia go na wycinkach logu tamtego przebiegu.
(
set +e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

scan="$tmp/scan.sh"
block scan-unread-bytecode > "$scan"
[ -s "$scan" ] \
  || fail 'the next-JDK leg must fail on bytecode a tool cannot read, but upstream-canary.yml has no scan-unread-bytecode block'

run_scan() {
  : > "$tmp/output"
  BUILD_LOG="$1" NEXT=28 GITHUB_OUTPUT="$tmp/output" bash "$scan" > "$tmp/stdout" 2>&1
  status=$?
  tools=$(sed -n 's/^tools=//p' "$tmp/output")
}

cat > "$tmp/spotbugs.log" <<'LOG'
> Task :spotbugsMain
The following errors occurred during analysis:

  Error scanning example/library/Greeting for referenced classes
    java.lang.IllegalArgumentException: Unsupported class file major version 72
      At org.objectweb.asm.ClassReader.<init>(ClassReader.java:200)
      At org.objectweb.asm.ClassReader.<init>(ClassReader.java:180)
      At org.objectweb.asm.ClassReader.<init>(ClassReader.java:166)
      At edu.umd.cs.findbugs.asm.FBClassReader.<init>(FBClassReader.java:35)
  Unable to get XClass for java/lang/Object
    java.lang.IllegalArgumentException: Unsupported class file major version 72
> Task :spotbugsMain
      At org.objectweb.asm.ClassReader.<init>(ClassReader.java:200)
      At org.objectweb.asm.ClassReader.<init>(ClassReader.java:180)
      At org.objectweb.asm.ClassReader.<init>(ClassReader.java:166)
      At edu.umd.cs.findbugs.asm.FBClassReader.<init>(FBClassReader.java:35)

edu.umd.cs.findbugs.NoClassesFoundToAnalyzeException: No classes found to analyze
SpotBugs ended with exit code 4

BUILD SUCCESSFUL in 31s
LOG

cat > "$tmp/jacoco.log" <<'LOG'
> Task :testClasses
java.lang.instrument.IllegalClassFormatException: Error while instrumenting sun/util/resources/cldr/provider/CLDRLocaleDataMetaInfo with JaCoCo 0.8.15.202606040825/6c5260a.
    at org.jacoco.agent.rt.internal_bac9136.CoverageTransformer.transform(CoverageTransformer.java:94)
> Task :test
    at java.instrument/java.lang.instrument.ClassFileTransformer.transform(ClassFileTransformer.java:257)
Caused by: java.lang.IllegalArgumentException: Unsupported class file major version 72
    at org.jacoco.agent.rt.internal_bac9136.asm.ClassReader.<init>(ClassReader.java:200)
    at org.jacoco.agent.rt.internal_bac9136.asm.ClassReader.<init>(ClassReader.java:180)
    ... 34 more

> Task :jacocoTestReport FAILED
LOG
cat "$tmp/spotbugs.log" >> "$tmp/jacoco.log"

cat > "$tmp/unknown.log" <<'LOG'
java.lang.IllegalArgumentException: Unsupported class file major version 72
    at org.objectweb.asm.ClassReader.<init>(ClassReader.java:200)
    at com.example.analyzer.Reader.read(Reader.java:12)
LOG

cat > "$tmp/clean.log" <<'LOG'
> Task :spotbugsMain
> Task :check
> Task :build

BUILD SUCCESSFUL in 31s
LOG

run_scan "$tmp/spotbugs.log"
[ "$status" -ne 0 ] || fail 'a report-only SpotBugs that cannot read the bytecode must fail the step even when the build passes'
[ "$tools" = 'SpotBugs' ] || fail "the step must name SpotBugs, named: '$tools'"
grep -q '^::error::SpotBugs cannot read the bytecode of the Java 28 toolchain' "$tmp/stdout" \
  || fail 'the step must annotate the run with the tools that cannot read the bytecode'

run_scan "$tmp/jacoco.log"
[ "$status" -ne 0 ] || fail 'JaCoCo and SpotBugs that cannot read the bytecode must fail the step'
[ "$tools" = 'JaCoCo, SpotBugs' ] || fail "the step must name JaCoCo and SpotBugs once each, named: '$tools'"

run_scan "$tmp/unknown.log"
[ "$status" -ne 0 ] || fail 'a tool without a known package must still fail the step'
[ "$tools" = 'an unidentified tool' ] || fail "an unknown tool must be reported as unidentified, named: '$tools'"

run_scan "$tmp/clean.log"
[ "$status" -eq 0 ] || fail 'a build whose tools read the bytecode must pass the step'
[ -z "$tools" ] || fail "a clean build must name no tool, named: '$tools'"

run_scan "$tmp/missing.log"
[ "$status" -eq 0 ] || fail 'without a build log (the build stopped before the starter) the step has nothing to add'

echo 'OK: the next-JDK canary fails on bytecode a tool cannot read and names the tools'
)

# --- checkstyle-toolchain ---
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
(
set +e
init="$root/.github/upstream-canary/checkstyle-on-canon-toolchain.init.gradle.kts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT


[ -f "$init" ] \
  || fail 'the next-JDK leg must run Checkstyle on the canon toolchain (gradle/gradle#39837), but .github/upstream-canary/checkstyle-on-canon-toolchain.init.gradle.kts is missing'

canon=$(sed -n -E 's/^java *= *"([0-9]+)".*/\1/p' "$root/gradle/catalog/libs.versions.toml")
[ -n "$canon" ] || fail 'gradle/catalog/libs.versions.toml has no java version'

block next-jdk-versions > "$tmp/versions.sh"
[ -s "$tmp/versions.sh" ] || fail 'upstream-canary.yml has no next-jdk-versions block'
(cd "$root" && GITHUB_OUTPUT="$tmp/versions.out" bash "$tmp/versions.sh") || fail 'the next-jdk-versions block failed'
[ "$(sed -n 's/^canon=//p' "$tmp/versions.out")" = "$canon" ] \
  || fail "the next-JDK leg must name the canon toolchain $canon for Checkstyle, named: '$(sed -n 's/^canon=//p' "$tmp/versions.out")'"
[ "$(sed -n 's/^version=//p' "$tmp/versions.out")" = "$((canon + 1))" ] \
  || fail "the next-JDK leg must still build on Java $((canon + 1))"

block next-jdk-starter-build > "$tmp/build.sh"
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
)
