#!/usr/bin/env node
// platform-versions-check — guard governance wersji frontendu (tryb STRICT).
// Porównuje dependencies/devDependencies z package.json (cwd) z versions.json tej paczki.
// Reguły:
//   1. KAŻDA zależność (poza @dominiksienkiewicz/* — pin platformy) musi mieć wpis w kanonie.
//   2. Wersja musi być IDENTYCZNA z kanonem (exact, bez ^/~).
// Nowa biblioteka w repo = najpierw wpis w Platform versions.json + release, potem użycie.
// Exit 1 przy naruszeniu — krok w reusable frontend-ci failuje build.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const canon = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "versions.json"), "utf8"),
).versions;
const pkg = JSON.parse(readFileSync(join(process.cwd(), "package.json"), "utf8"));

const declared = { ...pkg.dependencies, ...pkg.devDependencies };
const drift = [];
const missing = [];
for (const [name, have] of Object.entries(declared)) {
  if (name.startsWith("@dominiksienkiewicz/")) continue; // pin platformy — poza kanonem
  const want = canon[name];
  if (want === undefined) missing.push({ name, have });
  else if (have !== want) drift.push({ name, have, want });
}

if (drift.length === 0 && missing.length === 0) {
  const governed = Object.keys(declared).filter((n) => !n.startsWith("@dominiksienkiewicz/")).length;
  console.log(
    `platform-versions-check: OK (${governed} zależności pod governance, kanon: ${Object.keys(canon).length} pozycji)`,
  );
  process.exit(0);
}

if (missing.length > 0) {
  console.error("platform-versions-check: zależności BEZ wpisu w kanonie Platform:");
  for (const m of missing) console.error(`  ${m.name} (${m.have}) — dodaj do Platform versions.json i wydaj (./release.sh)`);
}
if (drift.length > 0) {
  console.error("platform-versions-check: DRYF wersji względem kanonu Platform:");
  for (const d of drift) console.error(`  ${d.name}: zadeklarowano "${d.have}", kanon "${d.want}"`);
}
console.error('Napraw: ./platform-bump.sh (nakłada kanon) albo świadomie zmień kanon w Platform.');
process.exit(1);
