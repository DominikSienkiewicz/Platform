#!/usr/bin/env bash
# contracts/problem-detail.json (złoty przykład, który czytają test platform-web-starter i test api-client)
# zgadza się z komponentem contracts/problem-detail.openapi.yaml: wymagane pola są, a żadne pole nie wychodzi
# poza schemat — inaczej snippet w specu konsumenta rozjechałby się z tym, co starter naprawdę wysyła.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
python3 -I - "$root/contracts/problem-detail.json" "$root/contracts/problem-detail.openapi.yaml" <<'PY'
import json, re, sys
golden = json.load(open(sys.argv[1]))
schema_text = open(sys.argv[2]).read()

def block(name):
    match = re.search(r"^    " + name + r":\n((?:      .*\n|\n)+)", schema_text, re.M)
    if not match:
        sys.exit(f"FAIL: the snippet has no schema {name}")
    body = match.group(1)
    properties = re.findall(r"^        ([a-zA-Z]+):", body, re.M)
    required = re.search(r"^      required: \[([^\]]*)\]", body, re.M)
    return set(properties), {r.strip() for r in required.group(1).split(",")} if required else set()

def check(value, schema, where):
    properties, required = block(schema)
    missing = required - set(value)
    extra = set(value) - properties
    if missing:
        sys.exit(f"FAIL: {where} lacks the required {sorted(missing)} of {schema}")
    if extra:
        sys.exit(f"FAIL: {where} has {sorted(extra)}, which {schema} does not describe")

check(golden, "ProblemDetail", "problem-detail.json")
for index, error in enumerate(golden.get("errors", [])):
    check(error, "ProblemFieldError", f"errors[{index}]")
if golden.get("message") != golden.get("detail"):
    sys.exit("FAIL: the legacy message must equal detail")
PY
echo 'OK: the golden Problem Details body matches the OpenAPI component'
