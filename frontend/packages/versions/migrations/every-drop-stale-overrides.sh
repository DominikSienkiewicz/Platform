# shellcheck shell=bash
# Override paczki, której kanon wydania docelowego już nie zna, jest pinem CVE po naprawie upstreamu: guard
# i tak go odrzuca. Usuwa takie wpisy z frontend/package.json (CLAUDE.md, zasada 6); piny Platform i referencje
# "$nazwa" zostają. Kanon: PLATFORM_CANON = versions.json wydania docelowego.
describe() { echo "remove frontend overrides of packages the canon no longer lists"; }
touches() { [[ -f frontend/package.json ]] && echo frontend/package.json; return 0; }
detect() { [[ -f frontend/package.json && -f "${PLATFORM_CANON:-}" ]] || return 1; python3 "$MIGRATION_LIB/stale_overrides.py" detect "$PLATFORM_CANON"; }
apply() { python3 "$MIGRATION_LIB/stale_overrides.py" apply "$PLATFORM_CANON"; }
