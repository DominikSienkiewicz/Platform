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
// --fix (offline): przepisuje rozjechane wersje i piny platformy na kanon zainstalowanej paczki; wpisów nie dodaje
// ani nie usuwa, więc zależność bez wpisu w kanonie zostaje błędem. W GitHub Actions (GITHUB_ACTIONS=true) każde
// naruszenie to adnotacja ::error z plikiem i linią, a tabela trafia do $GITHUB_STEP_SUMMARY.
import { appendFileSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const packageDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const canonFile = JSON.parse(readFileSync(join(packageDir, "versions.json"), "utf8"));
const canon = canonFile.versions;
// Kanał deprecacji (N-REL-9): paczka, która dalej działa, ale zniknie z kanonu — ostrzeżenie, nie czerwony build.
/** @type {Record<string, { since: string, removeIn: string, replacement: string }>} */
const deprecated = canonFile.deprecated ?? {};
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
const fix = process.argv.includes("--fix");
const manifestPath = join(process.cwd(), "package.json");
const manifestText = readFileSync(manifestPath, "utf8");
const pkg = JSON.parse(manifestText);

// Płaska lista {name, have, at, node, key} ze wszystkich rządzonych sekcji. `at` służy do raportu: dla overrides
// jest ścieżką (overrides.next.postcss), dla zależności bezpośredniej — null; node/key to miejsce do --fix.
const declared = [];
for (const section of ["dependencies", "devDependencies", "optionalDependencies"]) {
  for (const [name, have] of Object.entries(pkg[section] ?? {}))
    declared.push({ name, have, at: null, node: pkg[section], key: name });
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
    else if (typeof value === "string" && name) declared.push({ name, have: value, at, node, key });
  }
}
collectOverrides(pkg.overrides, "overrides", null);

let drift = [];
const missing = [];
let governed = 0;
for (const entry of declared) {
  const { name, have } = entry;
  if (name.startsWith("@dominiksienkiewicz/")) continue; // pin platformy — poza kanonem
  if (have.startsWith("$")) continue; // referencja npm ("$typescript") — wersję rozwija npm
  governed += 1;
  const want = canon[name];
  if (want === undefined) missing.push(entry);
  else if (have !== want) drift.push({ ...entry, want });
}

// Bez znanej wersji kanonu (kopia testowa) wymagamy przynajmniej jednej wspólnej wartości wszystkich pinów.
const platformPins = declared.filter(({ name, at }) => at === null && name.startsWith("@dominiksienkiewicz/"));
const pinValues = new Set(platformPins.map(({ have }) => have));
const expectedPin = canonVersion ?? (pinValues.size === 1 ? [...pinValues][0] : null);
let looseOrMixedPins = platformPins.filter(({ have }) => !/^\d+\.\d+\.\d+$/.test(have) || have !== expectedPin);

if (fix && (drift.length > 0 || (canonVersion && looseOrMixedPins.length > 0))) {
  const fixedPins = canonVersion ? looseOrMixedPins : [];
  for (const d of drift) d.node[d.key] = d.want;
  for (const p of fixedPins) p.node[p.key] = canonVersion;
  writeFileSync(manifestPath, `${JSON.stringify(pkg, null, 2)}\n`);
  console.log("platform-versions-check --fix: rewrote package.json to the canon:");
  for (const d of drift) console.log(`  ${d.name}${d.at ? ` [${d.at}]` : ""}: ${d.have} -> ${d.want}`);
  for (const p of fixedPins) console.log(`  ${p.name}: ${p.have} -> ${canonVersion}`);
  console.log("Then run npm install --package-lock-only and commit both files.");
  drift = [];
  looseOrMixedPins = looseOrMixedPins.filter((p) => !fixedPins.includes(p));
}

// Kody bramek (N-SHOW-8) z linkiem do docs wydania, z którego pochodzi kanon.
/** @param {string} code */
const gateLink = (code) =>
  `https://github.com/DominikSienkiewicz/Platform/blob/v${canonVersion ?? "main"}/docs/gates.md#${code.toLowerCase()}`;
const deprecations = declared.filter(({ name }) => deprecated[name]);
for (const d of deprecations) {
  const { since, removeIn, replacement } = deprecated[d.name];
  const text = `${d.name}${d.at ? ` [${d.at}]` : ""} is deprecated since Platform ${since} and goes in ${removeIn}: use ${replacement}`;
  console.warn(`[PLAT-DEPR-001] platform-versions-check: ${text} (${gateLink("PLAT-DEPR-001")})`);
  if (process.env.GITHUB_ACTIONS === "true") console.log(`::warning title=Platform deprecation::${text}`);
}

// Okno wsparcia (N-REL-6, RELEASING.md „Support policy”): kanon starszy niż 60 dni od wydania daje jedną linię,
// nigdy błąd, bo bramka zależna od czasu zrobiłaby stare commity nieodtwarzalnymi. releasedAt stempluje release.yml;
// PLATFORM_STALENESS_TODAY tylko dla testów, PLATFORM_STALENESS_NOTICE=false wycisza.
const SUPPORT_WINDOW_DAYS = 60;
if (typeof canonFile.releasedAt === "string" && process.env.PLATFORM_STALENESS_NOTICE !== "false") {
  const today = Date.parse(process.env.PLATFORM_STALENESS_TODAY ?? new Date().toISOString().slice(0, 10));
  const age = Math.floor((today - Date.parse(canonFile.releasedAt)) / 86_400_000);
  if (age > SUPPORT_WINDOW_DAYS) {
    const text =
      `Platform ${canonVersion ?? "canon"} was released ${age} days ago (${canonFile.releasedAt}); the support window is ` +
      `${SUPPORT_WINDOW_DAYS} days or 3 releases (RELEASING.md, Support policy). Run scripts/platform-bump.sh, or silence ` +
      "this notice with PLATFORM_STALENESS_NOTICE=false.";
    console.log(text);
    if (process.env.GITHUB_ACTIONS === "true") console.log(`::notice title=Platform support window::${text}`);
  }
}

if (drift.length === 0 && missing.length === 0 && looseOrMixedPins.length === 0) {
  console.log(
    `platform-versions-check: OK (${governed} governed dependencies, canon ${canonLabel} with ${Object.keys(canon).length} entries)`,
  );
  process.exit(0);
}

/** @param {{ at: string | null }} e */
const where = (e) => (e.at ? ` [${e.at}]` : "");
const platformCanon = "frontend/packages/versions/versions.json in DominikSienkiewicz/Platform";

// GitHub Actions: adnotacja na linii wpisu w package.json (pierwsze wystąpienie "nazwa": "wersja") i tabela w podsumowaniu.
if (process.env.GITHUB_ACTIONS === "true") {
  const lines = manifestText.split("\n");
  const file = relative(realpathSync(process.env.GITHUB_WORKSPACE ?? process.cwd()), realpathSync(manifestPath));
  /** @param {{ name: string, have: string }} e */
  const lineOf = (e) => {
    const index = lines.findIndex((line) => line.includes(`"${e.name}": "${e.have}"`) || line.includes(`"${e.have}"`) && line.includes('"."'));
    return index >= 0 ? index + 1 : 1;
  };
  const rows = [
    ...missing.map((m) => ({ e: m, text: `${m.name}${where(m)} ${m.have} has no canon entry` })),
    ...drift.map((d) => ({ e: d, text: `${d.name}${where(d)} declared ${d.have}, canon ${d.want}` })),
    ...looseOrMixedPins.map((p) => ({ e: p, text: `${p.name} declared ${p.have}, expected ${expectedPin ?? "one exact version"}` })),
  ];
  for (const { e, text } of rows) console.log(`::error file=${file},line=${lineOf(e)},title=Platform canon::${text}`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    const table = rows.map(({ e, text }) => `| \`${file}:${lineOf(e)}\` | ${text} |`).join("\n");
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `## Platform version canon (${canonLabel})\n\n| Where | Violation |\n|---|---|\n${table}\n\n` +
        `Fix the drift offline with \`platform-versions-check --fix\`, or run \`scripts/platform-bump.sh\`.\n`,
    );
  }
}
console.error(`platform-versions-check (canon: ${canonLabel})`);
if (missing.length > 0) {
  console.error("[PLAT-FE-001] platform-versions-check: dependencies without a Platform canon entry:");
  for (const m of missing)
    console.error(`  ${m.name}${where(m)} (${m.have}): add it to ${platformCanon}, release, then bump`);
}
if (drift.length > 0) {
  console.error("[PLAT-FE-002] platform-versions-check: versions that differ from the Platform canon:");
  for (const d of drift) console.error(`  ${d.name}${where(d)}: declared "${d.have}", canon "${d.want}"`);
}
if (looseOrMixedPins.length > 0) {
  const release = canonVersion ? `, the canon release ${canonVersion}` : "";
  console.error(`[PLAT-FE-003] platform-versions-check: Platform packages must share one exact version${release}:`);
  for (const p of looseOrMixedPins) console.error(`  ${p.name}: declared "${p.have}"`);
}
// Guard biegnie z frontend/ (working-directory frontend-ci), a stub żyje w <repo>/scripts/ — stąd „from the root”.
console.error(
  `Fix: run platform-versions-check --fix for drift (offline), or from the repository root run ` +
    `scripts/platform-bump.sh ${canonVersion ?? "<version>"} (applies the canon), or change ${platformCanon} and release.`,
);
const codes = [
  ...(missing.length > 0 ? ["PLAT-FE-001"] : []),
  ...(drift.length > 0 ? ["PLAT-FE-002"] : []),
  ...(looseOrMixedPins.length > 0 ? ["PLAT-FE-003"] : []),
];
for (const code of codes) console.error(`  ${code}: ${gateLink(code)}`);
process.exit(1);
