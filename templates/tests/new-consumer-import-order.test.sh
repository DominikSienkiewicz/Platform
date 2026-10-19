#!/usr/bin/env bash
# scripts/new-consumer.sh zostawia importy w kolejności google-java-format także wtedy, gdy nowy pakiet sortuje się
# za org.* (pl.example.bank): podmieniony prefiks nie może zostać na starym miejscu, bo spotlessCheck świeżo
# wygenerowanego repo byłby czerwony (GeneratedConsumerFunctionalTest w build-logic).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

static_imports() { sed -nE 's/^import static ([^ ;]+);$/\1/p' "$1"; }
plain_imports() { sed -nE '/^import static /d; s/^import ([^ ;]+);$/\1/p' "$1"; }

for package in pl.example.bank com.acme.orders; do
  name="${package##*.}-service"
  bash "$root/scripts/new-consumer.sh" --name "$name" --package "$package" --kind spring-app --out "$tmp/$name" > /dev/null
  while IFS= read -r -d '' file; do
    for group in static_imports plain_imports; do
      actual=$("$group" "$file")
      expected=$(LC_ALL=C sort <<< "$actual")
      [[ "$actual" == "$expected" ]] || fail "${file#"$tmp"/}: the imports must keep the google-java-format order:
$expected
instead of
$actual"
    done
  done < <(find "$tmp/$name/backend/src" -name '*.java' -print0)
done

welcome="$tmp/bank-service/backend/src/main/java/pl/example/bank/notifications/WelcomeNotifications.java"
[[ "$(plain_imports "$welcome" | tail -n 1)" == pl.example.bank.accounts.AccountOpened ]] \
  || fail 'an import of a package that sorts after org.* must come after the org.* imports'

echo 'OK: new-consumer keeps the imports of the rendered starter in google-java-format order'
