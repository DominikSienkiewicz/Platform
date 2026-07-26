#!/usr/bin/env node
// platform-versions-check — guard governance wersji frontendu (tryb STRICT).
// Porównuje dependencies/devDependencies/overrides z package.json (cwd) z versions.json tej paczki.
// Reguły:
//   1. KAŻDA zależność (poza @dominiksienkiewicz/* — pin platformy) musi mieć wpis w kanonie.
//   2. Wersja musi być IDENTYCZNA z kanonem (exact, bez ^/~).
// Nowa biblioteka w repo = najpierw wpis w Platform versions.json + release, potem użycie.
// `overrides` podlega tym samym regułom co zależność bezpośrednia — to tam żyją piny CVE paczek
// transytywnych (overrides.next.postcss), które bez tego dryfowały po cichu przy ruchu kanonu.
// Exit 1 przy naruszeniu — krok w reusable frontend-ci failuje build.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const canon = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "versions.json"), "utf8"),
).versions;
const pkg = JSON.parse(readFileSync(join(process.cwd(), "package.json"), "utf8"));

// Płaska lista {name, have, at} ze wszystkich rządzonych sekcji. `at` służy tylko do raportu:
// dla overrides jest ścieżką (overrides.next.postcss), dla zależności bezpośredniej — null.
const declared = [];
for (const section of ["dependencies", "devDependencies"]) {
  for (const [name, have] of Object.entries(pkg[section] ?? {})) declared.push({ name, have, at: null });
}

// npm `overrides`: wartość to wersja (string) albo zagnieżdżony obiekt zawężający kontekst
// (overrides.next.postcss = "postcss tylko pod next"). Klucz "." oznacza paczkę nadrzędną.
function collectOverrides(node, path, parent) {
  if (node === null || typeof node !== "object") return;
  for (const [key, value] of Object.entries(node)) {
    const name = key === "." ? parent : key;
    const at = key === "." ? path : `${path}.${key}`;
    if (value !== null && typeof value === "object") collectOverrides(value, at, name);
    else if (typeof value === "string" && name) declared.push({ name, have: value, at });
  }
}
collectOverrides(pkg.overrides, "overrides", null);

const drift = [];
const missing = [];
let governed = 0;
for (const { name, have, at } of declared) {
  if (name.startsWith("@dominiksienkiewicz/")) continue; // pin platformy — poza kanonem
  if (have.startsWith("$")) continue; // referencja npm ("$typescript") — wersję rozwija npm
  governed += 1;
  const want = canon[name];
  if (want === undefined) missing.push({ name, have, at });
  else if (have !== want) drift.push({ name, have, want, at });
}

if (drift.length === 0 && missing.length === 0) {
  console.log(
    `platform-versions-check: OK (${governed} zależności pod governance, kanon: ${Object.keys(canon).length} pozycji)`,
  );
  process.exit(0);
}

const where = (e) => (e.at ? ` [${e.at}]` : "");
if (missing.length > 0) {
  console.error("platform-versions-check: zależności BEZ wpisu w kanonie Platform:");
  for (const m of missing)
    console.error(`  ${m.name}${where(m)} (${m.have}) — dodaj do Platform versions.json i wydaj (./release.sh)`);
}
if (drift.length > 0) {
  console.error("platform-versions-check: DRYF wersji względem kanonu Platform:");
  for (const d of drift) console.error(`  ${d.name}${where(d)}: zadeklarowano "${d.have}", kanon "${d.want}"`);
}
console.error('Napraw: ./platform-bump.sh (nakłada kanon) albo świadomie zmień kanon w Platform.');
process.exit(1);
