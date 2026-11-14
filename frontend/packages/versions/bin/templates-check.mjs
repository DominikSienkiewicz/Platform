#!/usr/bin/env node
// platform-templates-check — compares the files a consumer copied from Platform's templates/ with the
// canon of its pinned release (templates/manifest.json) and prints DRIFT or MISSING with the command
// that restores each file. It only reports: the exit code is 0 whatever it finds, also when the canon
// cannot be fetched, so a bump or a build never fails on it.
//
//   platform-templates-check [--ref vX.Y.Z] [--root DIR] [--canon-dir DIR]
//
// --ref defaults to the release of this package, --root to the working directory. --canon-dir reads
// the canon from a local templates/ directory instead of raw.githubusercontent.com.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const repo = process.env.PLATFORM_REPO ?? "DominikSienkiewicz/Platform";

function options(argv) {
  const known = new Set(["--ref", "--root", "--canon-dir"]);
  const parsed = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!known.has(argv[i]) || argv[i + 1] === undefined) {
      console.error("Usage: platform-templates-check [--ref vX.Y.Z] [--root DIR] [--canon-dir DIR]");
      process.exit(2);
    }
    parsed[argv[i].slice(2)] = argv[i + 1];
  }
  return parsed;
}

function canonReader(ref, canonDir) {
  if (canonDir) {
    return async (path) => {
      const file = join(canonDir, path);
      return existsSync(file) ? readFileSync(file) : null;
    };
  }
  return async (path) => {
    const response = await fetch(`https://raw.githubusercontent.com/${repo}/${ref}/templates/${path}`);
    if (response.status === 404) return null;
    if (!response.ok) throw new Error(`HTTP ${response.status} for templates/${path}`);
    return Buffer.from(await response.arrayBuffer());
  };
}

/** Status of every manifest entry: OK, DRIFT, MISSING, or UNUSED for an absent optional file. */
export async function compare(entries, readCanon, root) {
  const results = [];
  for (const entry of entries) {
    const local = join(root, entry.target);
    if (!existsSync(local)) {
      results.push({ ...entry, status: entry.optional ? "UNUSED" : "MISSING" });
      continue;
    }
    const canon = await readCanon(entry.source);
    if (canon === null) throw new Error(`templates/${entry.source} is in the manifest but not in the canon`);
    results.push({ ...entry, status: canon.equals(readFileSync(local)) ? "OK" : "DRIFT" });
  }
  return results;
}

async function main() {
  const args = options(process.argv.slice(2));
  const ref = args.ref ?? `v${JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).version}`;
  const root = args.root ?? process.cwd();
  const readCanon = canonReader(ref, args["canon-dir"]);
  console.log(`platform-templates-check: comparing copied templates with ${repo} ${ref}`);
  try {
    const manifest = await readCanon("manifest.json");
    if (manifest === null) {
      console.log(`  ${ref} has no templates/manifest.json; it predates the check, so nothing is compared.`);
      return;
    }
    const results = await compare(JSON.parse(manifest.toString("utf8")).files, readCanon, root);
    const findings = results.filter((result) => result.status === "DRIFT" || result.status === "MISSING");
    for (const { status, source, target } of findings) {
      console.log(`  ${status.padEnd(7)} ${target}`);
      console.log(`          curl -fsSL https://raw.githubusercontent.com/${repo}/${ref}/templates/${source} -o ${target}`);
    }
    const compared = results.filter((result) => result.status !== "UNUSED").length;
    console.log(
      findings.length === 0
        ? `  OK: ${compared} copied templates match the canon.`
        : `  ${findings.length} of ${compared} templates are missing or differ from the canon; restore them with the commands above, or keep a deliberate fork.`,
    );
  } catch (error) {
    console.log(`  Skipped: the canon could not be read (${error.message}).`);
  }
}

await main();
