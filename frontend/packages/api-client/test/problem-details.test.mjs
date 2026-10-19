import assert from "node:assert/strict";
import test from "node:test";
import { ApiError, createApiClient } from "../index.js";

function clientForResponse(context, response) {
  context.mock.method(globalThis, "fetch", async () => response);
  return createApiClient({ baseUrl: "https://example.test" });
}

const problemHeaders = { "Content-Type": "application/problem+json" };

test("problem+json errors expose the problem and take the message from detail", async (context) => {
  const problem = {
    type: "https://example.test/problems/validation",
    title: "Bad Request",
    status: 400,
    detail: "name must not be blank",
    instance: "/orders",
    errors: [{ pointer: "#/name", detail: "must not be blank" }],
  };
  const client = clientForResponse(context, new Response(JSON.stringify(problem), { status: 400, headers: problemHeaders }));

  await assert.rejects(client.post("/orders", {}), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.message, problem.detail);
    assert.deepEqual(error.problem, problem);
    assert.equal(error.problem.errors.length, 1);
    assert.deepEqual(error.body, problem);
    return true;
  });
});

test("a problem without detail falls back to title, and the status comes from the response", async (context) => {
  const client = clientForResponse(
    context,
    new Response(JSON.stringify({ title: "Conflict" }), { status: 409, statusText: "Conflict!", headers: problemHeaders }),
  );

  await assert.rejects(client.get("/orders/1"), (error) => {
    assert.equal(error.message, "Conflict");
    assert.equal(error.problem.status, 409);
    return true;
  });
});

test("plain JSON errors keep problem null, so the legacy message shape is unchanged", async (context) => {
  const client = clientForResponse(context, new Response(JSON.stringify({ message: "Validation failed" }), { status: 400 }));

  await assert.rejects(client.get("/orders"), (error) => {
    assert.equal(error.message, "Validation failed");
    assert.equal(error.problem, null);
    return true;
  });
});

test("detail wins over a legacy message field copied next to it", async (context) => {
  const body = { detail: "Order 7 was changed by someone else", message: "Order 7 was changed by someone else", status: 409 };
  const client = clientForResponse(context, new Response(JSON.stringify(body), { status: 409, headers: problemHeaders }));

  await assert.rejects(client.get("/orders/7"), (error) => {
    assert.equal(error.message, body.detail);
    return true;
  });
});
