# shellcheck shell=bash
# Od 1.8.0 build-logic to bytecode 27, więc Gradle musi jechać na JDK 27 (ADR-0034). Callery reusable workflowów
# Platform z literalnym java-version < 27 i .sdkmanrc idą na 27; kryteria demona Gradle'a i inne setup-java = ręcznie.
GRADLE_JAVA=27
SDKMAN_JAVA="27-tem"
describe() { echo "run Gradle on Java $GRADLE_JAVA: java-version of the Platform callers and .sdkmanrc"; }
touches() {
  local file
  for file in .github/workflows/*.yml .github/workflows/*.yaml .sdkmanrc backend/.sdkmanrc; do [[ -f "$file" ]] && echo "$file"; done
  return 0
}
detect() { python3 "$MIGRATION_LIB/gradle_jdk.py" detect "$GRADLE_JAVA" "$SDKMAN_JAVA"; }
apply() { python3 "$MIGRATION_LIB/gradle_jdk.py" apply "$GRADLE_JAVA" "$SDKMAN_JAVA"; }
