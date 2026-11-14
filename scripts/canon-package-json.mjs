#!/usr/bin/env node
// canon-package-json — package.json konsumenta, który zależy od KAŻDEGO wpisu kanonu frontendu.
// canon-cve-scan.yml rozwiązuje z niego lockfile i skanuje dokładnie te wersje, które Platform narzuca.
//
//   node scripts/canon-package-json.mjs <ścieżka/do/versions.json> > package.json
//
// Paczki @dominiksienkiewicz/* to piny platformy, nie wpisy kanonu, więc wypadają. `overrides` z referencją
// "$nazwa" daje każdemu wystąpieniu paczki z kanonu, także tranzytywnemu, wersję kanonu: skan odpowiada
// na pytanie, czy podatny jest SAM kanon, a nie przypadkowy stary rodzic.
import { readFileSync } from "node:fs";

const [canonPath] = process.argv.slice(2);
if (!canonPath) {
  console.error("Usage: node scripts/canon-package-json.mjs <versions.json>");
  process.exit(2);
}

const { versions } = JSON.parse(readFileSync(canonPath, "utf8"));
const names = Object.keys(versions)
  .filter((name) => !name.startsWith("@dominiksienkiewicz/"))
  .sort();
const manifest = {
  name: "platform-canon-probe",
  version: "0.0.0",
  private: true,
  dependencies: Object.fromEntries(names.map((name) => [name, versions[name]])),
  overrides: Object.fromEntries(names.map((name) => [name, `$${name}`])),
};
process.stdout.write(`${JSON.stringify(manifest, null, 2)}\n`);
