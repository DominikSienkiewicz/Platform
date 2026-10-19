#!/usr/bin/env bash
# platform-doctor — read-only diagnosis of a consumer repository against Platform's preconditions (N-DX-1).
# Each check prints PASS, WARN or FAIL with a stable ID, what it saw and the fix; secrets are named by their
# source, never printed. Exit 1 only when a check FAILs. Run it from anywhere in the repository:
#   frontend/node_modules/.bin/platform-doctor [--offline] [--gradle]
# --offline skips the two checks that call GitHub Packages (PD031, PD043).
# --gradle also runs the Gradle-side checks of the platformDoctor task (PD080-PD082) through the wrapper.
set -uo pipefail

offline=0
gradle=0
for arg in "$@"; do
  case "$arg" in
    --offline) offline=1 ;;
    --gradle) gradle=1 ;;
    *) echo "usage: platform-doctor [--offline] [--gradle]" >&2; exit 2 ;;
  esac
done
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "FAIL PD001 not inside a git repository"; exit 1; }
cd "$root" || exit 1
OWNER=DominikSienkiewicz
failures=0
report() { # report <PASS|WARN|FAIL> <ID> <message> [fix]
  printf '%-4s %s %s\n' "$1" "$2" "$3"
  [[ -z "${4:-}" ]] || printf '          fix: %s\n' "$4"
  [[ "$1" != FAIL ]] || failures=$((failures + 1))
}
version_key() { local IFS=.; read -r -a part <<<"$1"; printf '%05d%05d%05d' "${part[0]:-0}" "${part[1]:-0}" "${part[2]:-0}"; }
is_blank() { [[ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]]; } # pusta albo z samych białych znaków, jak isNotBlank() w Gradle

# --- Pins ------------------------------------------------------------------------------------------------
pins=()
if [[ -f backend/settings.gradle.kts ]]; then
  while IFS= read -r pin; do pins+=("backend/settings.gradle.kts $pin"); done < <(
    grep -oE 'platform-catalog:[0-9]+\.[0-9]+\.[0-9]+|seniordev\.settings-conventions"\)[[:space:]]+version[[:space:]]+"[0-9]+\.[0-9]+\.[0-9]+' backend/settings.gradle.kts \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+$')
fi
for props in backend/gradle.properties gradle.properties; do
  [[ -f "$props" ]] || continue
  pin=$(sed -n -E 's/^platformVersion=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$props" | head -1)
  [[ -z "$pin" ]] || pins+=("$props $pin")
done
if [[ -f frontend/package.json ]]; then
  # shellcheck disable=SC2016 # the ${…} belong to the inline JavaScript template literal
  while IFS= read -r pin; do pins+=("frontend/package.json $pin"); done < <(
    node -e '
      const m = require(process.argv[1]);
      for (const s of ["dependencies", "devDependencies"])
        for (const [n, v] of Object.entries(m[s] ?? {})) if (n.startsWith("@dominiksienkiewicz/")) console.log(`${n} ${v}`);
    ' "$root/frontend/package.json" 2>/dev/null)
fi
values=$(printf '%s\n' "${pins[@]+"${pins[@]}"}" | awk '{print $NF}' | sort -u | grep -v '^$' || true)
PIN=$(head -1 <<<"$values")
if [[ -z "$values" ]]; then
  report FAIL PD020 "no Platform pin in backend/settings.gradle.kts, a gradle.properties or frontend/package.json" \
    "pin the release as docs/consuming.md shows"
elif [[ $(grep -c . <<<"$values") -gt 1 ]]; then
  report FAIL PD020 "the Platform pins disagree: $(printf '%s; ' "${pins[@]}")" "run scripts/platform-bump.sh <version> to move them together"
  PIN=$(sort -t. -k1,1n -k2,2n -k3,3n <<<"$values" | tail -1)
else
  report PASS PD020 "every Platform pin is $PIN (${#pins[@]} pins)"
fi

refs=$(grep -rhoE "uses:[[:space:]]*$OWNER/Platform/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml@[^[:space:]]+" .github/workflows 2>/dev/null \
  | sed -E 's/.*@//' | sort | uniq -c | awk '{print $2 " (" $1 ")"}' | tr '\n' ' ')
if [[ -z "$refs" ]]; then
  report PASS PD021 "no caller of Platform's reusable workflows"
elif [[ -n "$PIN" ]] && [[ "$refs" == "v$PIN ("*")"* ]] && [[ $(wc -w <<<"$refs") -eq 2 ]]; then
  report PASS PD021 "every reusable workflow reference is v$PIN"
else
  report WARN PD021 "reusable workflow references: $refs; Decision 3 pins them to the exact release" \
    "scripts/platform-bump.sh moves them to v${PIN:-<pin>}"
fi

# --- Gradle side -----------------------------------------------------------------------------------------
has_gradle=0
if [[ -f backend/settings.gradle.kts || -f settings.gradle.kts ]]; then has_gradle=1; fi
if [[ "$has_gradle" -eq 1 ]]; then
  java_line=$(java -version 2>&1 | head -1)
  java_major=$(sed -n -E 's/.*version "([0-9]+).*/\1/p' <<<"$java_line")
  if [[ -z "$java_major" ]]; then
    report FAIL PD010 "no java on PATH" "install JDK 25 or newer to run Gradle (README, Requirements)"
  elif [[ "$java_major" -lt 25 ]]; then
    report FAIL PD010 "java on PATH is $java_major; Platform's plugins are compiled for 25" "run Gradle on JDK 25 or newer (JAVA_HOME)"
  else
    report PASS PD010 "java on PATH is $java_major"
  fi
  wrapper_dir=backend; [[ -f backend/settings.gradle.kts ]] || wrapper_dir=.
  if [[ -x "$wrapper_dir/gradlew" ]]; then
    report PASS PD011 "$wrapper_dir/gradlew is executable"
  else
    report FAIL PD011 "$wrapper_dir/gradlew is missing or not executable" "copy the wrapper from Platform (templates/jvm/java-library) and chmod +x it"
  fi
  if [[ "$gradle" -eq 1 && -x "$wrapper_dir/gradlew" ]]; then
    # Wiersze taska mają format tego binu; liczą się jego FAIL-e. Brak wierszy = Gradle nie doszedł do taska.
    gradle_out=$(cd "$wrapper_dir" && ./gradlew -q --console=plain platformDoctor 2>&1)
    gradle_status=$?
    doctor_lines=$(grep -E '^(PASS|WARN|FAIL) PD08[0-9] |^          fix: ' <<<"$gradle_out" || true)
    if [[ -n "$doctor_lines" ]]; then
      printf '%s\n' "$doctor_lines"
      failures=$((failures + $(grep -c '^FAIL ' <<<"$doctor_lines")))
    elif [[ "$gradle_status" -ne 0 ]]; then
      reason=$(sed -n '/^\* What went wrong:/{n;p;q;}' <<<"$gradle_out")
      [[ -n "$reason" ]] || reason=$(grep -m1 -E '[^[:space:]]' <<<"$gradle_out")
      report FAIL PD083 "$wrapper_dir/gradlew platformDoctor did not run: $reason" \
        "pin a Platform release that has the platformDoctor task (CHANGELOG), then rerun; the Gradle output says what failed"
    fi
  fi
fi

# Pusty token albo złożony z samych białych znaków liczy się jak brak, jak w settings.gradle.kts (N-DX-18), i przechodzi
# do następnego źródła; devcontainer przekazuje nieustawioną zmienną hosta jako "".
gpr_key=""
[[ ! -f "$HOME/.gradle/gradle.properties" ]] || gpr_key=$(grep -E '^gpr\.key=' "$HOME/.gradle/gradle.properties" | cut -d= -f2- | tr -d ' ')
source_name="" token=""
if ! is_blank "${GPR_TOKEN:-}"; then source_name=GPR_TOKEN; token=$GPR_TOKEN
elif ! is_blank "${GITHUB_TOKEN:-}"; then source_name=GITHUB_TOKEN; token=$GITHUB_TOKEN
elif ! is_blank "$gpr_key"; then source_name="gpr.key in ~/.gradle/gradle.properties"; token=$gpr_key
fi
if [[ -z "$token" ]]; then
  report FAIL PD030 "no GitHub Packages credentials (GPR_TOKEN, GITHUB_TOKEN or gpr.key)" \
    "add a classic PAT with read:packages as gpr.key to ~/.gradle/gradle.properties (docs/local-development.md)"
else
  report PASS PD030 "credentials come from $source_name"
fi
if [[ "$offline" -eq 0 && -n "$token" && -n "$PIN" ]]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --proto '=https' -u "${GITHUB_ACTOR:-platform-doctor}:$token" \
    "https://maven.pkg.github.com/$OWNER/Platform/pl/seniordeveloper/platform-catalog/$PIN/platform-catalog-$PIN.pom" 2>/dev/null || true)
  case "$code" in
    200) report PASS PD031 "the catalog $PIN resolves from GitHub Packages" ;;
    401) report FAIL PD031 "GitHub Packages rejected the credentials from $source_name (401)" "use a classic PAT, not a fine-grained one, and check that it has not expired" ;;
    403) report FAIL PD031 "the credentials from $source_name may not read Platform's packages (403)" "give the PAT the read:packages scope" ;;
    404) report FAIL PD031 "platform-catalog $PIN is not published (404)" "pin a released version (RELEASING.md) or check releases/yanked.txt" ;;
    *) report WARN PD031 "GitHub Packages did not answer (HTTP ${code:-none})" "retry, or pass --offline" ;;
  esac
fi

# Login do Gradle: preflight w settings.gradle.kts i settings plugin chcą gpr.user albo GITHUB_ACTOR, a pusta lub
# złożona z samych białych znaków wartość liczy się jak brak (N-DX-18). W devcontainerze z tokenem i bez loginu
# PD030 i PD031 przechodzą, a Gradle staje na „No GitHub Packages credentials”. Tylko pliki i środowisko, bez sieci;
# drukujemy źródło, nie wartość.
if [[ "$has_gradle" -eq 1 ]]; then
  gradle_properties="$HOME/.gradle/gradle.properties"
  gpr_user=""
  # Properties.load: ostatni wpis klucza wygrywa; `gpr.username=` i wiersze komentarza (#, !) nie pasują do wzorca
  [[ ! -f "$gradle_properties" ]] || gpr_user=$(sed -n -E 's/^[[:space:]]*gpr\.user[[:space:]]*[=:](.*)$/\1/p' "$gradle_properties" | tail -n 1)
  login_source=""
  if ! is_blank "$gpr_user"; then login_source="gpr.user in ~/.gradle/gradle.properties"
  elif ! is_blank "${GITHUB_ACTOR:-}"; then login_source=GITHUB_ACTOR
  fi
  if [[ -n "$login_source" ]]; then
    report PASS PD032 "the GitHub login for Gradle comes from $login_source"
  else
    report WARN PD032 "no GitHub login for Gradle (gpr.user / GITHUB_ACTOR); the settings preflight stops with \"No GitHub Packages credentials\" even when a token is set" \
      "set gpr.user=<your GitHub login> in ~/.gradle/gradle.properties, or export GITHUB_ACTOR; an empty or whitespace-only value counts as missing"
  fi
fi

if [[ -f backend/Dockerfile ]]; then
  image=$(sed -n -E 's/^FROM[[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?([^[:space:]]+).*/\2/p' backend/Dockerfile | tail -1)
  runtime=$(sed -n -E 's/^(eclipse-temurin|sapmachine|amazoncorretto|openjdk):([0-9]+).*/\2/p' <<<"$image")
  if [[ -n "$runtime" ]] && [[ "$runtime" -lt 27 ]] && [[ -n "$PIN" ]] && ! [[ "$(version_key "$PIN")" < "$(version_key 1.5.29)" ]]; then
    report FAIL PD060 "backend/Dockerfile runs $image, older than the Java 27 toolchain of $PIN" "move the final FROM to the image in templates/Dockerfile.backend"
  elif [[ -n "$image" ]]; then
    report PASS PD060 "backend/Dockerfile runs $image"
  fi
fi

if [[ -f .secrets.local ]] || [[ -f scripts/setup-gh-deploy.sh ]]; then
  if git check-ignore -q .secrets.local; then
    report PASS PD050 ".secrets.local is ignored"
  else
    report FAIL PD050 ".secrets.local is not ignored, so deploy secrets could be committed" "add .secrets.local to .gitignore (templates/gitignore/root.gitignore)"
  fi
fi

# --- Frontend side ---------------------------------------------------------------------------------------
if [[ -f frontend/package.json ]]; then
  if grep -qxF "@dominiksienkiewicz:registry=https://npm.pkg.github.com" frontend/.npmrc 2>/dev/null; then
    report PASS PD040 "frontend/.npmrc points @dominiksienkiewicz at GitHub Packages"
  else
    report FAIL PD040 "frontend/.npmrc has no @dominiksienkiewicz registry line" "copy templates/npmrc to frontend/.npmrc"
  fi
  node_version=$(node --version 2>/dev/null | tr -d v)
  if [[ -z "$node_version" ]]; then
    report FAIL PD041 "no node on PATH" "install Node 24 (frontend/.nvmrc) or at least 22.13"
  elif [[ "$(version_key "$node_version")" < "$(version_key 22.13.0)" ]]; then
    report FAIL PD041 "node is $node_version; Platform's packages need 22.13 or newer" "install Node 24 (frontend/.nvmrc)"
  else
    report PASS PD041 "node is $node_version"
  fi
  if [[ -f frontend/package-lock.json ]]; then
    report PASS PD042 "frontend/package-lock.json is committed for npm ci"
  else
    report FAIL PD042 "frontend/package-lock.json is missing; frontend-ci installs with npm ci" "run npm install in frontend/ and commit package-lock.json"
  fi
  if [[ "$offline" -eq 0 && -n "$PIN" && -n "$token" ]]; then
    if (cd frontend && GITHUB_TOKEN="$token" npm view "@dominiksienkiewicz/versions@$PIN" version >/dev/null 2>&1); then
      report PASS PD043 "@dominiksienkiewicz/versions@$PIN resolves through frontend/.npmrc"
    else
      report FAIL PD043 "npm cannot read @dominiksienkiewicz/versions@$PIN" "check the token from $source_name and frontend/.npmrc"
    fi
  fi
fi

case "${AI_AGENT:-}" in
  1 | true) report PASS PD070 "AI_AGENT is on: scripts/agent-gradle.sh limits workers and test slots" ;;
  *) report PASS PD070 "AI_AGENT is off: Gradle runs with its defaults" ;;
esac

echo ""
if [[ "$failures" -gt 0 ]]; then
  echo "$failures check(s) failed; the IDs are explained in docs/consuming.md (Troubleshooting)."
  exit 1
fi
echo "Every check passed."
