import assert from "node:assert/strict";
import test from "node:test";

const cases = [
  { agent: "1", ci: undefined, maxWorkers: 2 },
  { agent: "true", ci: undefined, maxWorkers: 2 },
  { agent: undefined, ci: undefined, maxWorkers: undefined },
  { agent: "", ci: undefined, maxWorkers: undefined },
  { agent: "0", ci: undefined, maxWorkers: undefined },
  { agent: "false", ci: undefined, maxWorkers: undefined },
  { agent: "TRUE", ci: undefined, maxWorkers: undefined },
  { agent: undefined, ci: "true", maxWorkers: undefined },
  { agent: "true", ci: "true", maxWorkers: 2 },
];

for (const [index, { agent, ci, maxWorkers }] of cases.entries()) {
  test(`worker budget with AI_AGENT=${JSON.stringify(agent)} and CI=${JSON.stringify(ci)}`, async (context) => {
    const previousAgent = process.env.AI_AGENT;
    const previousCi = process.env.CI;
    context.after(() => {
      setEnvironment("AI_AGENT", previousAgent);
      setEnvironment("CI", previousCi);
    });
    setEnvironment("AI_AGENT", agent);
    setEnvironment("CI", ci);

    const { baseConfig } = await import(`../index.js?agent-budget=${index}`);

    assert.equal(baseConfig.test.maxWorkers, maxWorkers);
    assert.equal(Object.hasOwn(baseConfig.test, "maxWorkers"), maxWorkers !== undefined);
  });
}

function setEnvironment(name, value) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
