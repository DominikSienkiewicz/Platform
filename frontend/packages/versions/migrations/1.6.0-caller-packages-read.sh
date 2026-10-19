# shellcheck shell=bash
# Caller backend-ci.yml albo frontend-ci.yml musi nadać packages: read — inaczej run kończy się startup_failure
# bez logu (Attestate od 2026-10-14). Dopisuje packages: read do efektywnego bloku permissions callera.
describe() { echo "grant packages: read to the callers of backend-ci.yml and frontend-ci.yml"; }
touches() { local file; for file in .github/workflows/*.yml .github/workflows/*.yaml; do [[ -f "$file" ]] && echo "$file"; done; return 0; }
detect() { python3 "$MIGRATION_LIB/caller_permissions.py" detect; }
apply() { python3 "$MIGRATION_LIB/caller_permissions.py" apply; }
