import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** @param {Record<string, Record<string, string>>} manifest @param {Record<string, string>} companions */
export function missingCompanions(manifest, companions) {
  const sections = ["dependencies", "devDependencies", "optionalDependencies"];
  const missing = [];
  for (const [owner, companion] of Object.entries(companions)) {
    const section = sections.find((key) =>
      Object.hasOwn(manifest[key] ?? {}, owner),
    );
    if (
      section &&
      !sections.some((key) => Object.hasOwn(manifest[key] ?? {}, companion))
    ) {
      missing.push({ section, name: companion });
    }
  }
  return missing;
}

if (
  process.argv[1] &&
  realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const canon = JSON.parse(
    readFileSync(new URL("../../versions.json", import.meta.url), "utf8"),
  );
  const path = "frontend/package.json";
  const manifest = JSON.parse(readFileSync(path, "utf8"));
  const missing = missingCompanions(manifest, canon.companions ?? {});
  if (process.argv[2] === "detect") {
    process.exitCode = missing.length ? 0 : 1;
  } else if (process.argv[2] === "apply" && missing.length) {
    for (const { section, name } of missing)
      manifest[section][name] = canon.versions[name];
    writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
  }
}
