#!/usr/bin/env bash
# scripts/new-consumer.sh przenosi podpakiety startera (moduły Spring Modulith spring-app) razem z katalogami
# i podmienia prefiks pakietu w deklaracjach package i w importach, także gdy nowy pakiet leży pod katalogiem
# szablonu (example.shop).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

render() { bash "$root/scripts/new-consumer.sh" --name "$1" --package "$2" --kind spring-app --out "$tmp/$1" > /dev/null; }
sources() { (cd "$1" && find . -type f | sort); }

render account-service pl.example.bank
backend="$tmp/account-service/backend"
for source_set in main test; do
  expected=$(sources "$root/templates/jvm/spring-app/src/$source_set/java/example/app")
  actual=$(sources "$backend/src/$source_set/java/pl/example/bank")
  [[ "$actual" == "$expected" ]] || fail "src/$source_set: every file of the starter must keep its sub-package:
$actual
instead of
$expected"
done
main="$backend/src/main/java/pl/example/bank"
grep -qx 'package pl.example.bank.accounts;' "$main/accounts/Accounts.java" || fail 'a module must get the new package'
grep -qx 'package pl.example.bank.notifications;' "$main/notifications/WelcomeNotifications.java" \
  || fail 'every module must get the new package'
grep -qx 'import pl.example.bank.accounts.AccountOpened;' "$main/notifications/WelcomeNotifications.java" \
  || fail 'an import between modules must get the new package'
grep -qx 'package pl.example.bank;' "$backend/src/test/java/pl/example/bank/ApplicationTest.java" \
  || fail 'the test sources must get the new package'
if grep -rqF 'example.app' "$backend/src"; then fail 'no reference to the template package may remain'; fi
[[ ! -e "$backend/src/main/java.rendered" ]] || fail 'the staging directory must be gone'

render shop-service example.shop
shop="$tmp/shop-service/backend/src/main/java/example"
[[ -f "$shop/shop/Application.java" && -f "$shop/shop/accounts/Accounts.java" ]] \
  || fail 'a package under the template directory must keep the rendered files'
[[ ! -d "$shop/app" ]] || fail 'the template package must be gone'
grep -qx 'import example.shop.accounts.AccountOpened;' "$shop/shop/notifications/WelcomeNotifications.java" \
  || fail 'the import must point at the new package'

echo 'OK: new-consumer renders the sub-packages of the starter with the new package'
