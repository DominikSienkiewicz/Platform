#!/usr/bin/env node
// platform-versions-check — guard governance wersji frontendu (tryb STRICT).
// Porównuje dependencies/devDependencies/optionalDependencies/overrides z package.json (cwd)
// z versions.json tej paczki. peerDependencies aplikacji są świadomie poza governance.
// Reguły:
//   1. KAŻDA zależność (poza @dominiksienkiewicz/* — pin platformy) musi mieć wpis w kanonie.
//   2. Wersja musi być IDENTYCZNA z kanonem (exact, bez ^/~).
//   3. Piny @dominiksienkiewicz/* (poza overrides) są EXACT i równe wydaniu, z którego pochodzi kanon —
//      kanon z versions@X i preset z eslint-config@Y nie mogą pochodzić z różnych wydań.
// Nowa biblioteka w repo = najpierw wpis w Platform versions.json + release, potem użycie.
// `overrides` podlega tym samym regułom co zależność bezpośrednia — to tam żyją piny CVE paczek
// transytywnych (overrides.next.postcss), które bez tego dryfowały po cichu przy ruchu kanonu.
// Exit 1 przy naruszeniu — krok w reusable frontend-ci failuje build.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const packageDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const canon = JSON.parse(readFileSync(join(packageDir, "versions.json"), "utf8")).versions;
// Wersja paczki versions = wydanie Platform, z którego pochodzi kanon (jedna platformVersion dla wszystkich
// paczek). Bez niej konsument nie wie, czy podbić pin, czy powtórzyć bump. Kopia bez package.json (testy
// hermetyczne) nie zna wersji — wtedy raport podaje ścieżkę versions.json.
const canonVersion = readCanonVersion();
const canonLabel = canonVersion ? `@dominiksienkiewicz/versions@${canonVersion}` : join(packageDir, "versions.json");

function readCanonVersion() {
  try {
    return JSON.parse(readFileSync(join(packageDir, "package.json"), "utf8")).version ?? null;
  } catch {
    return null;
  }
}
const pkg = JSON.parse(readFileSync(join(process.cwd(), "package.json"), "utf8"));

// Płaska lista {name, have, at} ze wszystkich rządzonych sekcji. `at` służy tylko do raportu:
// dla overrides jest ścieżką (overrides.next.postcss), dla zależności bezpośredniej — null.
const declared = [];
for (const section of ["dependencies", "devDependencies", "optionalDependencies"]) {
  for (const [name, have] of Object.entries(pkg[section] ?? {})) declared.push({ name, have, at: null });
}

// npm `overrides`: wartość to wersja (string) albo zagnieżdżony obiekt zawężający kontekst
// (overrides.next.postcss = "postcss tylko pod next"). Klucz "." oznacza paczkę nadrzędną.
/**
 * @param {unknown} node
 * @param {string} path
 * @param {string | null} parent
 */
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

// Bez znanej wersji kanonu (kopia testowa) wymagamy przynajmniej jednej wspólnej wartości wszystkich pinów.
const platformPins = declared.filter(({ name, at }) => at === null && name.startsWith("@dominiksienkiewicz/"));
const pinValues = new Set(platformPins.map(({ have }) => have));
const expectedPin = canonVersion ?? (pinValues.size === 1 ? [...pinValues][0] : null);
const looseOrMixedPins = platformPins.filter(({ have }) => !/^\d+\.\d+\.\d+$/.test(have) || have !== expectedPin);

if (drift.length === 0 && missing.length === 0 && looseOrMixedPins.length === 0) {
  console.log(
    `platform-versions-check: OK (${governed} governed dependencies, canon ${canonLabel} with ${Object.keys(canon).length} entries)`,
  );
  process.exit(0);
}

/** @param {{ at: string | null }} e */
const where = (e) => (e.at ? ` [${e.at}]` : "");
const platformCanon = "frontend/packages/versions/versions.json in DominikSienkiewicz/Platform";
console.error(`platform-versions-check (canon: ${canonLabel})`);
if (missing.length > 0) {
  console.error("platform-versions-check: dependencies without a Platform canon entry:");
  for (const m of missing)
    console.error(`  ${m.name}${where(m)} (${m.have}): add it to ${platformCanon}, release, then bump`);
}
if (drift.length > 0) {
  console.error("platform-versions-check: versions that differ from the Platform canon:");
  for (const d of drift) console.error(`  ${d.name}${where(d)}: declared "${d.have}", canon "${d.want}"`);
}
if (looseOrMixedPins.length > 0) {
  const release = canonVersion ? `, the canon release ${canonVersion}` : "";
  console.error(`platform-versions-check: Platform packages must share one exact version${release}:`);
  for (const p of looseOrMixedPins) console.error(`  ${p.name}: declared "${p.have}"`);
}
// Guard biegnie z frontend/ (working-directory frontend-ci), a stub żyje w <repo>/scripts/ — stąd „from the root”.
console.error(
  `Fix: from the repository root run scripts/platform-bump.sh ${canonVersion ?? "<version>"} (applies the canon), ` +
    `or change ${platformCanon} and release.`,
);
process.exit(1);
