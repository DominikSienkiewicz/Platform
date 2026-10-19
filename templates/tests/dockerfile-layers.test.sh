#!/usr/bin/env bash
# Warstwy obrazu z templates/Dockerfile.backend (N-CAP-5): ekstrakcja jara Boota w etapie `layers`, jeden COPY na
# warstwę w kolejności od najrzadziej zmienianej, launcher Boota zamiast `java -jar`, a opcjonalny cache AOT przez
# plik argumentów, pusty domyślnie. Ostatni FROM zostaje obrazem JRE (platformRuntimeImageCheck, PD060).
set -euo pipefail
dockerfile="$(cd "$(dirname "$0")/.." && pwd)/Dockerfile.backend"
fail() { echo "FAIL: $*" >&2; exit 1; }
grep -qE '^FROM sapmachine:[0-9]+-jre AS layers$' "$dockerfile" || fail 'the layers stage extracts on the runtime JRE'
grep -qF 'RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination extracted' "$dockerfile" \
  || fail 'the jar is extracted into its Boot layers with the launcher'
copies=$(sed -n -E 's#^COPY --from=layers /build/extracted/([a-z-]+)/ \./$#\1#p' "$dockerfile" | paste -sd' ' -)
[[ "$copies" == "dependencies spring-boot-loader snapshot-dependencies application" ]] \
  || fail "one COPY per Boot layer, least changing first (got: $copies)"
grep -qxF 'ARG AOT_CACHE=false' "$dockerfile" || fail 'the AOT cache is opt-in'
grep -qF 'java -XX:AOTCacheOutput=/app/app.aot -Dspring.context.exit=onRefresh' "$dockerfile" || fail 'the AOT cache is trained by one context refresh'
grep -qF 'else : > /app/jvm.args; fi' "$dockerfile" || fail 'without the AOT cache the argument file is empty'
grep -qxF 'ENTRYPOINT ["java", "@/app/jvm.args", "org.springframework.boot.loader.launch.JarLauncher"]' "$dockerfile" \
  || fail 'the entrypoint starts the Boot launcher with the argument file'
[[ "$(sed -n -E 's/^FROM[[:space:]]+([^[:space:]]+).*/\1/p' "$dockerfile" | tail -1)" =~ ^sapmachine:[0-9]+-jre$ ]] \
  || fail 'the final FROM stays the JRE image the runtime image gate reads'
echo 'OK: Dockerfile.backend copies each Boot layer once and makes the AOT cache opt-in'
