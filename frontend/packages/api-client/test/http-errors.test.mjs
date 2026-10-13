import assert from "node:assert/strict";
import test from "node:test";
import { ApiError, createApiClient } from "../index.js";

function clientForResponse(context, response) {
  context.mock.method(globalThis, "fetch", async () => response);
  return createApiClient({ baseUrl: "https://example.test" });
}

test("HTML error responses preserve the HTTP status and raw body", async (context) => {
  const html = "<html><body>Upstream unavailable</body></html>";
  const client = clientForResponse(
    context,
    new Response(html, { status: 503, statusText: "Service Unavailable" }),
  );

  await assert.rejects(client.get("/resource"), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.status, 503);
    assert.equal(error.message, "Service Unavailable");
    assert.equal(error.body, html);
    return true;
  });
});

test("non-JSON errors without a status message fall back to the HTTP status", async (context) => {
  const client = clientForResponse(context, new Response("upstream failure", { status: 500 }));

  await assert.rejects(client.get("/resource"), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.status, 500);
    assert.equal(error.message, "HTTP 500");
    assert.equal(error.body, "upstream failure");
    return true;
  });
});

test("JSON errors retain the parsed body and its message", async (context) => {
  const body = { message: "Validation failed", fields: ["name"] };
  const client = clientForResponse(
    context,
    new Response(JSON.stringify(body), { status: 400, statusText: "Bad Request" }),
  );

  await assert.rejects(client.get("/resource"), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.status, 400);
    assert.equal(error.message, body.message);
    assert.deepEqual(error.body, body);
    return true;
  });
});

test("empty error responses retain a null body", async (context) => {
  const client = clientForResponse(
    context,
    new Response(null, { status: 404, statusText: "Not Found" }),
  );

  await assert.rejects(client.get("/resource"), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.status, 404);
    assert.equal(error.message, "Not Found");
    assert.equal(error.body, null);
    return true;
  });
});

test("successful JSON responses retain the parsed body", async (context) => {
  const body = { id: 42 };
  const client = clientForResponse(context, new Response(JSON.stringify(body)));

  assert.deepEqual(await client.get("/resource"), body);
});

test("empty successful responses retain a null body", async (context) => {
  const client = clientForResponse(context, new Response(null));

  assert.equal(await client.get("/resource"), null);
});

test("204 responses return null without reading the body", async (context) => {
  const response = new Response(null, { status: 204 });
  const readBody = context.mock.method(response, "text");
  const client = clientForResponse(context, response);

  assert.equal(await client.get("/resource"), null);
  assert.equal(readBody.mock.callCount(), 0);
});

test("successful invalid JSON responses still reject with SyntaxError", async (context) => {
  const client = clientForResponse(context, new Response("<html>Unexpected success body</html>"));

  await assert.rejects(client.get("/resource"), SyntaxError);
});
