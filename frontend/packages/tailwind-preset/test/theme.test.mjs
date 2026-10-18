// theme.css runs through Tailwind here, before a consumer's `next build` would be the first to compile it:
// a syntax error, a renamed token or a dark-mode gap would otherwise reach three applications at once.
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { compile } from "tailwindcss";

const packageDir = fileURLToPath(new URL("..", import.meta.url));
const theme = await readFile(resolve(packageDir, "theme.css"), "utf8");
const button = await readFile(
  resolve(packageDir, "../ui-registry/registry/new-york/ui/button.tsx"),
  "utf8",
);
const require = createRequire(import.meta.url);

async function loadStylesheet(id, base) {
  const path = id === "tailwindcss" ? require.resolve("tailwindcss/index.css") : resolve(base, id);
  return { path, base: dirname(path), content: await readFile(path, "utf8") };
}

async function build(candidates) {
  const compiler = await compile('@import "./theme.css";\n@import "tailwindcss";\n', {
    base: packageDir,
    loadStylesheet,
  });
  return compiler.build(candidates);
}

function block(selector) {
  const start = theme.indexOf(`${selector} {`);
  assert.notEqual(start, -1, `theme.css has no "${selector} {" block`);
  return theme.slice(start, theme.indexOf("}", start));
}

const declaredTokens = (css) => new Set([...css.matchAll(/^\s*--([\w-]+):/gm)].map((match) => match[1]));

test("the preset compiles with Tailwind and its utilities resolve to the tokens", async () => {
  const css = await build(["bg-background", "text-primary-foreground", "bg-brand", "rounded-lg", "font-mono"]);
  assert.match(css, /var\(--background\)/);
  assert.match(css, /--color-brand/);
});

test("dark mode defines every token light mode defines", () => {
  assert.deepEqual([...declaredTokens(block(".dark"))].sort(), [...declaredTokens(block(":root"))].sort());
});

test("every light-mode token has a colour utility, and every mapping points at a defined token", () => {
  const tokens = declaredTokens(block(":root"));
  const inline = block("@theme inline");
  const mappings = [...inline.matchAll(/--color-([\w-]+):\s*var\(--([\w-]+)\)/g)];
  assert.deepEqual(
    mappings.filter(([, , target]) => !tokens.has(target)).map(([, name, target]) => `${name} -> --${target}`),
    [],
  );
  const mapped = new Set(mappings.map(([, name]) => name));
  assert.deepEqual([...tokens].filter((token) => !mapped.has(token)), []);
});

test("every colour utility of the registry button resolves against the preset", async () => {
  const variants = button.slice(button.indexOf("cva("), button.indexOf("defaultVariants"));
  const utilities = [...variants.matchAll(/"([^"]*)"/g)]
    .flatMap(([, classes]) => classes.split(/\s+/))
    .map((token) => token.slice(token.lastIndexOf(":") + 1).replace(/\/\d+$/, ""))
    .filter((utility) => /^(bg|text|border|ring|outline)(-|$)/.test(utility));
  const unique = [...new Set(utilities)];
  assert.ok(unique.includes("bg-primary"), "the button classes were not found in button.tsx");

  const css = await build(unique);
  const escape = (utility) => utility.replace(/[^\w-]/g, (character) => `\\${character}`);
  assert.deepEqual(unique.filter((utility) => !css.includes(`.${escape(utility)}`)), []);
});
