#!/usr/bin/env bash
# new-consumer.sh — render a new product repository from Platform's canon instead of assembling it by hand
# (N-DX-3). The layout is the one every consumer uses and platform-bump expects: backend/ next to the root files.
#
# Usage:
#   scripts/new-consumer.sh --name <name> --package <java.package> --kind spring-app|java-library --out <dir>
#                           [--platform-version X.Y.Z]
#
# Renders into <dir>, which must not exist yet:
#   backend/            templates/jvm/<kind> with the package, group and rootProject.name substituted, the Gradle
#                       wrapper of the java-library starter and platformVersion=<version> (default: this checkout's);
#   .github/workflows/  a ci.yml caller of backend-ci.yml at the exact tag v<version>, with packages: read and an
#                       explicit gpr_token secret (never secrets: inherit);
#   scripts/            platform-bump.sh, merge.sh, agent-gradle.sh, worktree-new.sh and worktree-status.sh;
#   root files          .gitignore, backend/.gitignore, .editorconfig and .sdkmanrc from templates/.
# It does not create a git repository, a remote or any GitHub setting; docs/consuming.md lists what follows.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
usage() { echo "usage: new-consumer.sh --name <name> --package <java.package> --kind spring-app|java-library --out <dir> [--platform-version X.Y.Z]" >&2; exit 2; }

name="" package="" kind="" out="" version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name=${2:-}; shift ;;
    --package) package=${2:-}; shift ;;
    --kind) kind=${2:-}; shift ;;
    --out) out=${2:-}; shift ;;
    --platform-version) version=${2:-}; shift ;;
    *) usage ;;
  esac
  shift
done
[[ -n "$name" && -n "$package" && -n "$kind" && -n "$out" ]] || usage
[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "--name must be kebab-case, e.g. order-service" >&2; exit 2; }
[[ "$package" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || { echo "--package must be a Java package such as pl.example.orders" >&2; exit 2; }
case "$kind" in spring-app) template_package=example.app ;; java-library) template_package=example.library ;; *) usage ;; esac
[[ -n "$version" ]] || version=$(sed -n 's/^platformVersion=//p' "$root/gradle/build-logic/gradle.properties")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "--platform-version must be X.Y.Z, got $version" >&2; exit 2; }
[[ ! -e "$out" ]] || { echo "$out already exists; pick a new directory." >&2; exit 2; }

templates="$root/templates"
mkdir -p "$out/backend" "$out/.github/workflows" "$out/scripts"

# backend/: starter, pakiet i nazwy; wrapper ze startera java-library (spring-app go nie niesie).
cp -R "$templates/jvm/$kind/." "$out/backend/"
cp "$templates/jvm/java-library/gradlew" "$templates/jvm/java-library/gradlew.bat" "$out/backend/"
mkdir -p "$out/backend/gradle" && cp -R "$templates/jvm/java-library/gradle/wrapper" "$out/backend/gradle/"
for source_set in main test; do
  from="$out/backend/src/$source_set/java/${template_package//.//}"
  to="$out/backend/src/$source_set/java/${package//.//}"
  [[ -d "$from" ]] || continue
  mkdir -p "$to"
  for file in "$from"/*.java; do
    sed "s/^package ${template_package//./\\.};/package $package;/" "$file" > "$to/${file##*/}"
  done
  rm -rf "$out/backend/src/$source_set/java/example"
done
sed -i.bak -E "s/^rootProject\.name = \".*\"$/rootProject.name = \"$name\"/" "$out/backend/settings.gradle.kts"
sed -i.bak -E "s/^group = \".*\"$/group = \"$package\"/" "$out/backend/build.gradle.kts"
sed -i.bak -E "s/^platformVersion=.*/platformVersion=$version/" "$out/backend/gradle.properties"
rm -f "$out"/backend/*.bak
cp "$templates/gitignore/backend.gitignore" "$out/backend/.gitignore"

cp "$templates/gitignore/root.gitignore" "$out/.gitignore"
cp "$templates/.editorconfig" "$out/.editorconfig"
cp "$templates/.sdkmanrc" "$out/.sdkmanrc"
for script in platform-bump.sh merge.sh agent-gradle.sh worktree-new.sh worktree-status.sh; do
  cp "$templates/$script" "$out/scripts/$script"
  chmod +x "$out/scripts/$script"
done

cat > "$out/.github/workflows/ci.yml" <<YML
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  packages: read

jobs:
  backend:
    uses: DominikSienkiewicz/Platform/.github/workflows/backend-ci.yml@v$version
    with:
      working-directory: backend
    secrets:
      gpr_token: \${{ secrets.GPR_TOKEN }}
YML

echo "Rendered $name ($kind, package $package, Platform $version) in $out."
echo "Next: git init, add the GPR_TOKEN secret, and build with (cd $out/backend && ./gradlew build)."
