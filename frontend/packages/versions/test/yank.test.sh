#!/usr/bin/env bash
# releases/yanked.txt: bump bez argumentu omija wycofane wydanie, jawny cel z listy wymaga --allow-yanked,
# a niedostępna lista tylko ostrzega (fail-open). Cały bin na atrapach (bump-fixture.sh).
set -euo pipefail
# shellcheck source-path=SCRIPTDIR source=bump-fixture.sh
source "$(dirname "$0")/bump-fixture.sh"

export FAKE_VERSIONS='[{"name":"1.5.31"},{"name":"1.5.30"},{"name":"1.5.29"}]'
export FAKE_YANKED='# version reason replacement
1.5.31 plugin markers missing 1.5.30'

dir=$(consumer latest)
bump "$dir" --dry-run
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'a bump without a version must succeed'; }
grep -qF '==> Podbijam piny Platform do: 1.5.30' "$dir.log" || { cat "$dir.log"; fail 'the yanked 1.5.31 must be skipped for 1.5.30'; }

bump "$dir" 1.5.31
[[ $rc -ne 0 ]] || { cat "$dir.log"; fail 'an explicit yanked target must be refused'; }
grep -qF 'Platform 1.5.31 is yanked: plugin markers missing 1.5.30' "$dir.log" || { cat "$dir.log"; fail 'the refusal must give the reason and replacement'; }
[[ -z "$(git -C "$dir" status --porcelain)" ]] || fail 'a refused yanked target must not change the tree'

bump "$dir" --dry-run --allow-yanked 1.5.31
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail '--allow-yanked must take the yanked target'; }
grep -qF 'WARNING: Platform 1.5.31 is yanked' "$dir.log" || fail '--allow-yanked must still warn'

FAKE_YANKED='' bump "$dir" --dry-run
[[ $rc -eq 0 ]] || { cat "$dir.log"; fail 'an unreachable yank list must not block the bump'; }
grep -qF 'could not read the list of yanked Platform releases' "$dir.log" || fail 'an unreachable yank list must warn'
grep -qF '==> Podbijam piny Platform do: 1.5.31' "$dir.log" || fail 'without the list the newest release is the target'

echo 'OK: platform-bump skips yanked releases and refuses an explicit one without --allow-yanked'
