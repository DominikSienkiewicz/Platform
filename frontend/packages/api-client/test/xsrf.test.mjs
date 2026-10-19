import assert from "node:assert/strict";
import test from "node:test";
import { createApiClient } from "../index.js";

// platform.security.csrf=spa: token z ciasteczka XSRF-TOKEN wraca w nagłówku X-XSRF-TOKEN.
function recordFetch(context) {
  const calls = [];
  context.mock.method(globalThis, "fetch", async (url, init) => {
    calls.push({ method: init.method, headers: new Headers(init.headers) });
    return new Response(null, { status: 204 });
  });
  return calls;
}

function withCookie(context, cookie) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, "document");
  Object.defineProperty(globalThis, "document", { value: { cookie }, configurable: true });
  context.after(() => {
    if (previous) Object.defineProperty(globalThis, "document", previous);
    else delete globalThis.document;
  });
}

test("xsrf echoes the cookie on unsafe methods only", async (context) => {
  const calls = recordFetch(context);
  withCookie(context, "theme=dark; XSRF-TOKEN=abc%3D%3D");
  const client = createApiClient({ baseUrl: "https://example.test", xsrf: true });

  await client.post("/orders", { id: 1 });
  await client.delete("/orders/1");
  await client.get("/orders");

  assert.equal(calls[0].headers.get("X-XSRF-TOKEN"), "abc==");
  assert.equal(calls[1].headers.get("X-XSRF-TOKEN"), "abc==");
  assert.equal(calls[2].headers.get("X-XSRF-TOKEN"), null, "a safe method needs no token");
});

test("xsrf takes custom names, and a header the call sets wins", async (context) => {
  const calls = recordFetch(context);
  withCookie(context, "CSRF=from-cookie");
  const client = createApiClient({ baseUrl: "https://example.test", xsrf: { cookie: "CSRF", header: "X-CSRF" } });

  await client.put("/orders/1", {});
  await client.put("/orders/1", {}, { headers: { "x-csrf": "explicit" } });

  assert.equal(calls[0].headers.get("X-CSRF"), "from-cookie");
  assert.equal(calls[1].headers.get("X-CSRF"), "explicit");
});

test("without the option or the cookie no header is added", async (context) => {
  const calls = recordFetch(context);
  withCookie(context, "XSRF-TOKEN=abc");

  await createApiClient({ baseUrl: "https://example.test" }).post("/orders", {});
  await createApiClient({ baseUrl: "https://example.test", xsrf: { cookie: "MISSING" } }).post("/orders", {});

  assert.equal(calls[0].headers.get("X-XSRF-TOKEN"), null, "xsrf is opt-in");
  assert.equal(calls[1].headers.get("X-XSRF-TOKEN"), null, "no cookie, no header");
});

test("outside the browser xsrf does nothing", async (context) => {
  const calls = recordFetch(context);
  assert.equal(typeof globalThis.document, "undefined");

  await createApiClient({ baseUrl: "https://example.test", xsrf: true }).post("/orders", {});

  assert.equal(calls[0].headers.get("X-XSRF-TOKEN"), null);
});
