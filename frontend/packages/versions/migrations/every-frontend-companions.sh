# shellcheck shell=bash
describe() { echo "install the compiler or peer required by the frontend toolchain"; }
touches() { if [[ -f frontend/package.json ]]; then echo frontend/package.json; fi; }
detect() { [[ -f frontend/package.json ]] && node "$MIGRATION_LIB/frontend-companions.mjs" detect; }
apply() { node "$MIGRATION_LIB/frontend-companions.mjs" apply; }
