import assert from "node:assert/strict";
import test from "node:test";
import { createApiClient } from "../index.js";

function recordFetch(context) {
  const calls = [];
  context.mock.method(globalThis, "fetch", async (url, init) => {
    calls.push({ url, headers: new Headers(init.headers) });
    return new Response(null, { status: 204 });
  });
  return calls;
}

test("headers passed as a Headers instance reach fetch", async (context) => {
  const calls = recordFetch(context);
  const client = createApiClient({ baseUrl: "https://example.test" });

  await client.get("/x", { headers: new Headers({ Authorization: "Bearer t" }) });

  assert.equal(calls[0].headers.get("Authorization"), "Bearer t");
  assert.equal(calls[0].headers.get("Content-Type"), "application/json");
});

test("headers passed as an array of pairs reach fetch", async (context) => {
  const calls = recordFetch(context);
  const client = createApiClient({ baseUrl: "https://example.test" });

  await client.get("/x", { headers: [["X-Trace", "1"]] });

  assert.equal(calls[0].headers.get("X-Trace"), "1");
  assert.equal(calls[0].headers.get("0"), null);
});

test("a call's Content-Type replaces the JSON default whatever its case", async (context) => {
  const calls = recordFetch(context);
  const client = createApiClient({ baseUrl: "https://example.test" });

  await client.post("/x", undefined, { headers: { "Content-Type": "text/plain" } });
  await client.post("/x", undefined, { headers: { "content-type": "text/plain" } });

  assert.equal(calls[0].headers.get("Content-Type"), "text/plain");
  assert.equal(calls[1].headers.get("Content-Type"), "text/plain");
});

test("a call's header replaces the client default of the same name", async (context) => {
  const calls = recordFetch(context);
  const client = createApiClient({
    baseUrl: "https://example.test",
    headers: { Authorization: "Bearer default" },
  });

  await client.get("/x");
  await client.get("/x", { headers: new Headers({ authorization: "Bearer call" }) });

  assert.equal(calls[0].headers.get("Authorization"), "Bearer default");
  assert.equal(calls[1].headers.get("Authorization"), "Bearer call");
});

test("without a baseUrl the client prefixes NEXT_PUBLIC_API_BASE_URL", async (context) => {
  const calls = recordFetch(context);
  const previous = process.env.NEXT_PUBLIC_API_BASE_URL;
  process.env.NEXT_PUBLIC_API_BASE_URL = "https://api.test";
  context.after(() => {
    if (previous === undefined) delete process.env.NEXT_PUBLIC_API_BASE_URL;
    else process.env.NEXT_PUBLIC_API_BASE_URL = previous;
  });

  await createApiClient().get("/x");

  assert.equal(calls[0].url, "https://api.test/x");
});
