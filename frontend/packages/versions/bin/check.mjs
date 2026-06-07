#!/usr/bin/env node
// platform-versions-check — guard dryfu wersji frontendu względem kanonu Platform.
// Porównuje dependencies/devDependencies z package.json (cwd) z versions.json tej paczki.
// Reguły: (1) klucz obecny w OBU → wersja musi być IDENTYCZNA (exact, bez ^/~),
//         (2) klucze spoza kanonu → ignorowane (zależności domenowe repo).
// Exit 1 przy dryfie — krok w reusable frontend-ci failuje build.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const canon = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "versions.json"), "utf8"),
).versions;
const pkg = JSON.parse(readFileSync(join(process.cwd(), "package.json"), "utf8"));

const declared = { ...pkg.dependencies, ...pkg.devDependencies };
const drift = [];
for (const [name, want] of Object.entries(canon)) {
  const have = declared[name];
  if (have === undefined) continue; // repo nie używa — OK
  if (have !== want) drift.push({ name, have, want });
}

if (drift.length === 0) {
  console.log(`platform-versions-check: OK (${Object.keys(canon).length} pozycji kanonu, 0 dryfu)`);
  process.exit(0);
}

console.error("platform-versions-check: DRYF wersji względem kanonu Platform:");
for (const d of drift) {
  console.error(`  ${d.name}: zadeklarowano "${d.have}", kanon "${d.want}"`);
}
console.error('Napraw: ./platform-bump.sh (nakłada kanon) albo świadomie zmień kanon w Platform.');
process.exit(1);
