import assert from "node:assert/strict";
import test from "node:test";

// AI_AGENT_MAX_WORKERS (N-SHOW-2): to samo pokrętło, które czyta scripts/agent-gradle.sh.
const cases = [
  { agent: "1", workers: "3", maxWorkers: 3 },
  { agent: "1", workers: undefined, maxWorkers: 2 },
  { agent: undefined, workers: "3", maxWorkers: undefined },
];

for (const [index, { agent, workers, maxWorkers }] of cases.entries()) {
  test(`maxWorkers with AI_AGENT=${JSON.stringify(agent)} and AI_AGENT_MAX_WORKERS=${JSON.stringify(workers)}`, async (context) => {
    restoreAfter(context, ["AI_AGENT", "AI_AGENT_MAX_WORKERS"]);
    setEnvironment("AI_AGENT", agent);
    setEnvironment("AI_AGENT_MAX_WORKERS", workers);

    const { baseConfig } = await import(`../index.js?agent-workers=${index}`);

    assert.equal(baseConfig.test.maxWorkers, maxWorkers);
  });
}

test("an invalid AI_AGENT_MAX_WORKERS fails with its value", async (context) => {
  restoreAfter(context, ["AI_AGENT", "AI_AGENT_MAX_WORKERS"]);
  setEnvironment("AI_AGENT", "1");
  setEnvironment("AI_AGENT_MAX_WORKERS", "many");

  await assert.rejects(import("../index.js?agent-workers=invalid"), /AI_AGENT_MAX_WORKERS must be a positive integer, got 'many'\./);
});

function restoreAfter(context, names) {
  const previous = Object.fromEntries(names.map((name) => [name, process.env[name]]));
  context.after(() => {
    for (const name of names) setEnvironment(name, previous[name]);
  });
}

function setEnvironment(name, value) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
