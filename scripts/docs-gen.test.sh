#!/usr/bin/env bash
# docs-gen.sh (N-SHOW-15): regiony w repo są aktualne (to jest bramka CI: job `templates` uruchamia ten test), a na
# atrapie nowe wejście workflowu, nowa paczka npm, zmieniony szablon i ADR dodany bez regeneracji indeksu failują
# --check; regeneracja je naprawia i drugi przebieg niczego nie zmienia. ADR bez tytułu albo statusu jest odrzucany.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; echo "${OUT:-}" >&2; exit 1; }
OUT=$(bash "$here/docs-gen.sh" --check) || fail 'the generated regions of the repository must be current; run scripts/docs-gen.sh'

fixture="$tmp/platform"
mkdir -p "$fixture/docs/adr" "$fixture/.github/workflows" "$fixture/frontend/packages/one" "$fixture/templates"
cat > "$fixture/.github/workflows/build.yml" <<'YAML'
on:
  workflow_call:
    inputs:
      task:
        description: "Gradle task to run."
        type: string
        default: "build"
jobs: {}
YAML
printf '{ "name": "@x/one", "description": "First package." }\n' > "$fixture/frontend/packages/one/package.json"
printf 'line one\nline two\n' > "$fixture/templates/snippet.txt"
printf '# Architecture decision records\n\nThe table below is generated.\n\n<!-- docs-gen:adr-index -->\n<!-- /docs-gen -->\n' > "$fixture/docs/adr/README.md"
printf '# ADR-0001: The first decision\n\n## Status\n\nAccepted\n' > "$fixture/docs/adr/0001-first.md"
cat > "$fixture/docs/reference.md" <<'MD'
# Reference

<!-- docs-gen:inputs build.yml -->
<!-- /docs-gen -->

<!-- docs-gen:npm-packages -->
<!-- /docs-gen -->

<!-- include: templates/snippet.txt#L2-L2 -->
```text
```
MD
run() { RC=0; OUT=$(python3 -I "$here/docs-gen.py" "$@" "$fixture" 2>&1) || RC=$?; }
run
grep -qF '| `task` | string | `build` | Gradle task to run. |' "$fixture/docs/reference.md" || fail 'the inputs table must be generated'
grep -qF '| `@x/one` | `frontend/packages/one/` | yes | — | First package. |' "$fixture/docs/reference.md" || fail 'the package table must be generated'
grep -qxF 'line two' "$fixture/docs/reference.md" || fail 'the include must hold exactly the requested lines'
grep -qxF 'line one' "$fixture/docs/reference.md" && fail 'lines outside the range stay out'
run --check
[[ $RC -eq 0 ]] || fail 'a fresh generation is current'

mkdir -p "$fixture/frontend/packages/two" && printf '{ "name": "@x/two", "private": true }\n' > "$fixture/frontend/packages/two/package.json"
run --check
[[ $RC -eq 1 ]] && grep -qF 'docs/reference.md' <<<"$OUT" || fail 'a package added without regenerating must fail --check'
run
run --check
[[ $RC -eq 0 ]] || fail 'regenerating fixes it'
printf 'line one\nline 2\n' > "$fixture/templates/snippet.txt"
run --check
[[ $RC -eq 1 ]] || fail 'a changed template must make its snippet stale'
run
grep -qxF '| [0001](0001-first.md) | The first decision | Accepted |' "$fixture/docs/adr/README.md" || fail 'the ADR index must be generated from the ADR headers'

printf '# ADR-0999: A decision nobody indexed\n\n## Status\n\nProposed\n' > "$fixture/docs/adr/0999-unindexed.md"
run --check
[[ $RC -eq 1 ]] && grep -qF 'docs/adr/README.md' <<<"$OUT" || fail 'an ADR missing from the index must fail --check'
run
grep -qxF '| [0999](0999-unindexed.md) | A decision nobody indexed | Proposed |' "$fixture/docs/adr/README.md" || fail 'regenerating must add the row'
run --check
[[ $RC -eq 0 ]] || fail 'the regenerated index must pass --check'
head -1 "$fixture/docs/adr/README.md" | grep -qF '# Architecture decision records' || fail 'the text above the table must stay'

printf 'no title\n' > "$fixture/docs/adr/0998-broken.md"
run
[[ $RC -ne 0 ]] || fail 'an ADR without a title must be refused'
grep -qF '0998-broken.md' <<<"$OUT" || fail 'the refusal must name the ADR file'
echo 'OK: docs-gen regenerates inputs, packages, snippets and the ADR index, and --check fails on stale regions'
