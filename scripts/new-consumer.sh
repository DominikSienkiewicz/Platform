#!/usr/bin/env bash
# new-consumer.sh — render a new product repository from Platform's canon instead of assembling it by hand
# (N-DX-3). The layout is the one every consumer uses and platform-bump expects: backend/ next to the root files.
#
# Usage:
#   scripts/new-consumer.sh --name <name> --package <java.package> --kind spring-app|java-library --out <dir>
#                           [--platform-version X.Y.Z] [--frontend next]
#
# Renders into <dir>, which must not exist yet:
#   backend/            templates/jvm/<kind> with the package, group and rootProject.name substituted, the Gradle
#                       wrapper of the java-library starter and platformVersion=<version> (default: this checkout's);
#   .github/workflows/  a ci.yml caller of backend-ci.yml at the exact tag v<version>, with packages: read and an
#                       explicit gpr_token secret (never secrets: inherit);
#   scripts/            platform-bump.sh, merge.sh, agent-gradle.sh, worktree-new.sh and worktree-status.sh;
#   root files          .gitignore, backend/.gitignore, .editorconfig and .sdkmanrc from templates/;
#   frontend/           with --frontend next: a Next.js app (src/ layout) whose package.json pins every dependency
#                       at the canon of frontend/packages/versions and every @dominiksienkiewicz/* package at
#                       <version>, the strict scripts (lint, typecheck, test, build, format:check), .npmrc, the
#                       tsconfig/eslint/vitest/prettier/Tailwind configs of the packages, next.config.ts,
#                       Dockerfile.frontend and the public/ directory it copies, plus a frontend-ci.yml caller
#                       with strict: true. Run npm install once
#                       to create package-lock.json, which npm ci in frontend-ci needs.
# It does not create a git repository, a remote or any GitHub setting; docs/consuming.md lists what follows.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
usage() { echo "usage: new-consumer.sh --name <name> --package <java.package> --kind spring-app|java-library --out <dir> [--platform-version X.Y.Z] [--frontend next]" >&2; exit 2; }

name="" package="" kind="" out="" version="" frontend=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name=${2:-}; shift ;;
    --package) package=${2:-}; shift ;;
    --kind) kind=${2:-}; shift ;;
    --out) out=${2:-}; shift ;;
    --platform-version) version=${2:-}; shift ;;
    --frontend) frontend=${2:-}; shift ;;
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
[[ -z "$frontend" || "$frontend" == next ]] || { echo "--frontend supports only next" >&2; exit 2; }
[[ -z "$frontend" ]] || command -v node >/dev/null || { echo "--frontend next needs node on PATH" >&2; exit 2; }
[[ ! -e "$out" ]] || { echo "$out already exists; pick a new directory." >&2; exit 2; }

templates="$root/templates"
mkdir -p "$out/backend" "$out/.github/workflows" "$out/scripts"

# backend/: starter, pakiet i nazwy; wrapper ze startera java-library (spring-app go nie niesie).
cp -R "$templates/jvm/$kind/." "$out/backend/"
cp "$templates/jvm/java-library/gradlew" "$templates/jvm/java-library/gradlew.bat" "$out/backend/"
mkdir -p "$out/backend/gradle" && cp -R "$templates/jvm/java-library/gradle/wrapper" "$out/backend/gradle/"
# Nowy prefiks importu może sortować się inaczej niż example.* (pl.* leży za org.*), a spotlessCheck wymaga
# kolejności google-java-format: każdy ciąg importów (grupa static i zwykła) bajtowo po nazwie.
sort_imports() {
  LC_ALL=C awk '
    function name(line) { sub(/^import (static )?/, "", line); sub(/;$/, "", line); return line }
    function flush(   i, j, line) {
      for (i = 2; i <= n; i++) {
        line = run[i]
        for (j = i - 1; j >= 1 && name(run[j]) > name(line); j--) run[j + 1] = run[j]
        run[j + 1] = line
      }
      for (i = 1; i <= n; i++) print run[i]
      n = 0
    }
    /^import / { run[++n] = $0; next }
    { flush(); print }
    END { flush() }
  '
}

# Podpakiety (moduły Spring Modulith startera spring-app) idą razem z katalogami, a prefiks pakietu znika też
# z importów. Najpierw do katalogu obok: pakiet docelowy może leżeć pod katalogiem szablonu (example.shop).
for source_set in main test; do
  java="$out/backend/src/$source_set/java"
  from="$java/${template_package//.//}"
  [[ -d "$from" ]] || continue
  rendered="$out/backend/src/$source_set/java.rendered"
  while IFS= read -r -d '' file; do
    relative=${file#"$from"/}
    mkdir -p "$rendered/$(dirname "$relative")"
    sed -E "s/^(package|import|import static) ${template_package//./\\.}([.;])/\1 $package\2/" "$file" \
      | sort_imports > "$rendered/$relative"
  done < <(find "$from" -type f -print0)
  rm -rf "${java:?}/${template_package%%.*}"
  mkdir -p "$java/${package//.//}"
  cp -R "$rendered/." "$java/${package//.//}/"
  rm -rf "$rendered"
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

if [[ "$frontend" == next ]]; then
  web="$out/frontend"
  mkdir -p "$web/src/app" "$web/public"
  # Etap runner Dockerfile.frontend kopiuje /app/public, a git nie przechowuje pustego katalogu.
  : > "$web/public/.gitkeep"
  cp "$templates/npmrc" "$web/.npmrc"
  cp "$templates/gitignore/frontend.gitignore" "$web/.gitignore"
  cp "$templates/frontend/next.config.ts" "$web/next.config.ts"
  cp "$templates/Dockerfile.frontend" "$web/Dockerfile"
  echo 24 > "$web/.nvmrc"
  # Wersje z kanonu tego checkoutu (frontend/packages/versions/versions.json): platform-versions-check przechodzi od razu.
  # Pliki niżej są już w formacie Prettiera (domyślne 80 kolumn), więc pierwszy `format:check` w CI jest zielony.
  node - "$root/frontend/packages/versions/versions.json" "$version" "$name" > "$web/package.json" <<'NODE'
const [canonPath, version, name] = process.argv.slice(2);
const canon = JSON.parse(require("node:fs").readFileSync(canonPath, "utf8")).versions;
const pick = (names) => Object.fromEntries(names.map((dependency) => {
  if (!canon[dependency]) throw new Error(`${dependency} has no entry in the canon`);
  return [dependency, canon[dependency]];
}));
const platform = ["eslint-config", "prettier-config", "tailwind-preset", "tsconfig", "versions", "vitest-config"]
  .map((packageName) => [`@dominiksienkiewicz/${packageName}`, version]);
const manifest = {
  name: `${name}-frontend`,
  version: "0.1.0",
  private: true,
  type: "module",
  scripts: {
    dev: "next dev",
    build: "next build",
    start: "next start",
    lint: "eslint .",
    typecheck: "tsc --noEmit",
    test: "vitest run",
    format: "prettier --write .",
    "format:check": "prettier --check .",
  },
  prettier: "@dominiksienkiewicz/prettier-config",
  dependencies: pick(["next", "react", "react-dom"]),
  devDependencies: Object.fromEntries(
    [
      ...platform,
      ...Object.entries(pick([
        "@tailwindcss/postcss", "@testing-library/jest-dom", "@testing-library/react", "@types/node", "@types/react",
        "@types/react-dom", "@vitejs/plugin-react", "eslint", "eslint-config-next", "jsdom", "prettier",
        "prettier-plugin-tailwindcss", "tailwindcss", "typescript", "vitest",
      ])),
    ].sort(([a], [b]) => a.localeCompare(b)),
  ),
};
process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
NODE
  cat > "$web/tsconfig.json" <<'JSON'
{
  "extends": "@dominiksienkiewicz/tsconfig/next.json",
  "compilerOptions": { "paths": { "@/*": ["./src/*"] } },
  "include": [
    "next-env.d.ts",
    "**/*.ts",
    "**/*.tsx",
    ".next/types/**/*.ts",
    ".next/dev/types/**/*.ts"
  ],
  "exclude": ["node_modules"]
}
JSON
  printf 'export { default } from "@dominiksienkiewicz/eslint-config/next";\n' > "$web/eslint.config.mjs"
  printf 'export default { plugins: { "@tailwindcss/postcss": {} } };\n' > "$web/postcss.config.mjs"
  cat > "$web/vitest.config.ts" <<'TS'
import { defineConfig, mergeConfig } from "vitest/config";
import { fileURLToPath } from "node:url";
import { baseConfig } from "@dominiksienkiewicz/vitest-config";

export default mergeConfig(
  baseConfig,
  defineConfig({
    resolve: {
      alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
    },
  }),
);
TS
  printf '@import "@dominiksienkiewicz/tailwind-preset/theme.css";\n@import "tailwindcss";\n' > "$web/src/app/globals.css"
  cat > "$web/src/app/layout.tsx" <<'TSX'
import type { ReactNode } from "react";
import "./globals.css";

export default function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
TSX
  cat > "$web/src/app/page.tsx" <<TSX
export default function Home() {
  return (
    <main>
      <h1>$name</h1>
    </main>
  );
}
TSX
  cat > "$web/src/app/page.test.tsx" <<TSX
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import Home from "./page";

describe("Home", () => {
  it("names the application", () => {
    render(<Home />);
    expect(screen.getByRole("heading", { name: "$name" })).toBeDefined();
  });
});
TSX
  cat >> "$out/.github/workflows/ci.yml" <<YML
  frontend:
    uses: DominikSienkiewicz/Platform/.github/workflows/frontend-ci.yml@v$version
    with:
      working-directory: frontend
      strict: true
    secrets:
      gpr_token: \${{ secrets.GPR_TOKEN }}
YML
fi

echo "Rendered $name ($kind, package $package, Platform $version) in $out."
echo "Next: git init, add the GPR_TOKEN secret, and build with (cd $out/backend && ./gradlew build)."
[[ -z "$frontend" ]] || echo "Frontend: (cd $out/frontend && npm install) creates package-lock.json; commit it, as npm ci needs it."
