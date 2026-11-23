import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [phase, frontend, assets] = process.argv.slice(2);
if (!["prepare", "verify-lock"].includes(phase) || !frontend || !assets) {
  throw new Error("Usage: legacy-frontend-smoke.mjs prepare|verify-lock FRONTEND ASSETS");
}

const version = "1.13.1";
const prefix = "@dominiksienkiewicz/";
const release = `https://github.com/SeniorDeveloper-pl-Dominik-Sienkiewicz/Platform/releases/download/v${version}`;
const manifestPath = join(frontend, "package.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const lock = phase === "verify-lock" ? JSON.parse(readFileSync(join(frontend, "package-lock.json"), "utf8")) : undefined;
const sums = new Map();
for (const line of readFileSync(join(assets, "SHA256SUMS"), "utf8").trimEnd().split("\n")) {
  const entry = /^([0-9a-f]{64}) {2}([a-zA-Z0-9._-]+)$/.exec(line);
  if (!entry || sums.has(entry[2])) throw new Error("Invalid release checksum manifest");
  sums.set(entry[2], entry[1]);
}

let verified = 0;
for (const dependencies of [manifest.dependencies ?? {}, manifest.devDependencies ?? {}]) {
  for (const [name, spec] of Object.entries(dependencies)) {
    if (name.startsWith("@seniordeveloper-pl-dominik-sienkiewicz/")) {
      throw new Error(`Unexpected organization dependency ${name} in the historical image smoke`);
    }
    if (!name.startsWith(prefix)) continue;
    const pkg = name.slice(prefix.length);
    if (!/^[a-z0-9][a-z0-9-]*$/.test(pkg)) throw new Error(`Invalid Platform package ${name}`);
    const archive = `dominiksienkiewicz-${pkg}-${version}.tgz`;
    const bytes = readFileSync(join(assets, archive));
    if (createHash("sha256").update(bytes).digest("hex") !== sums.get(archive)) {
      throw new Error(`Release checksum mismatch for ${archive}`);
    }
    const url = `${release}/${archive}`;
    if (phase === "prepare") {
      if (spec !== version) throw new Error(`Expected ${name} pinned to ${version}`);
      dependencies[name] = url;
    } else {
      const entry = lock.packages?.[`node_modules/${name}`];
      const integrity = "sha512-" + createHash("sha512").update(bytes).digest("base64");
      if (spec !== url || entry?.resolved !== url || entry.version !== version || entry.integrity !== integrity) {
        throw new Error(`npm lock does not identify the signed release tarball of ${name}`);
      }
    }
    verified++;
  }
}
if (!verified) throw new Error("No historical Platform packages in the generated frontend");
if (phase === "prepare") writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`${phase}: ${verified} Platform packages from the signed v${version} release`);
