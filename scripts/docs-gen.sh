#!/usr/bin/env bash
# docs-gen.sh [--check] — regeneruje oznaczone regiony Markdown ze źródeł (N-SHOW-15): wycinki kodu
# (<!-- include: … -->), tabele wejść reusable workflowów i tabelę paczek npm. --check niczego nie pisze i kończy
# się kodem 1, gdy region jest nieaktualny (ci.yml). Logika: scripts/docs-gen.py; test: scripts/docs-gen.test.sh.
set -euo pipefail
exec python3 -I "$(cd "$(dirname "$0")" && pwd)/docs-gen.py" "$@"
