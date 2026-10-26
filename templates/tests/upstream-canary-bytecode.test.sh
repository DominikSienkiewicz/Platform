#!/usr/bin/env bash
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
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
yaml="$root/.github/workflows/upstream-canary.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

scan="$tmp/scan.sh"
awk '/# >>> scan-unread-bytecode/{f=1;next} /# <<< scan-unread-bytecode/{f=0} f' "$yaml" > "$scan"
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
