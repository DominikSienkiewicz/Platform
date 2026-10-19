# shellcheck shell=bash
# Toolchain 27 wymaga runtime >= 27: ostatni FROM eclipse-temurin:2X-jre/-jdk (< 27) idzie na obraz z
# templates/Dockerfile.backend. Inny zapis obrazu Javy < 27 (alpine, digest, sapmachine) = ręcznie.
RUNTIME_IMAGE="sapmachine:27-jre"
describe() { echo "move the final Dockerfile stage to $RUNTIME_IMAGE, the runtime of the Java 27 toolchain"; }
touches() { local file; for file in backend/Dockerfile Dockerfile; do [[ -f "$file" ]] && echo "$file"; done; return 0; }
detect() { python3 "$MIGRATION_LIB/runtime_image.py" detect "$RUNTIME_IMAGE"; }
apply() { python3 "$MIGRATION_LIB/runtime_image.py" apply "$RUNTIME_IMAGE"; }
