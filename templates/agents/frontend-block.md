<!-- BEGIN platform-agents-frontend v{{VERSION}} (managed by platform-bump; edits inside these markers are replaced) -->
## Frontend rules for agents (Platform {{VERSION}})

The stack of Platform {{VERSION}}, taken from its frontend canon `versions.json` and enforced by
`platform-versions-check`: Next.js {{next}}, React {{react}}, TypeScript {{typescript}}, Tailwind CSS {{tailwindcss}},
Vitest {{vitest}}, ESLint {{eslint}}, Prettier {{prettier}}. Read versions from the canon, never from memory.

- Every version in `package.json`, `overrides` included, is exact and equal to the canon; a package the canon
  lacks is added in Platform first. `npx platform-versions-check --fix` rewrites drift offline.
- Use npm and commit `package-lock.json`, which `frontend-ci` installs with `npm ci`. Fix a CVE in a transitive
  package with `npm update <package> --package-lock-only` before reaching for an override.
- Shared configuration comes from the `@dominiksienkiewicz/*` presets (`tsconfig`, `eslint-config`,
  `prettier-config`, `vitest-config`, `tailwind-preset`): extend them, do not copy them.
- Run the `lint` and `format:check` scripts as the default gate and tests only when asked; with `AI_AGENT=1`,
  Vitest uses `AI_AGENT_MAX_WORKERS` workers (2 unless set).
- With `platform.openapi` in `package.json`, API types come from the committed spec through `platform-openapi-gen`,
  and `platform-openapi-check` fails on stale types: regenerate them, never edit them.
<!-- END platform-agents-frontend -->
