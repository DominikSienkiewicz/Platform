import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { ApiError, createApiClient } from "../index.js";

// Ten sam plik, który PlatformProblemDetailsContractTest porównuje z odpowiedzią platform-web-starter.
const golden = JSON.parse(await readFile(new URL("../../../../contracts/problem-detail.json", import.meta.url), "utf8"));

test("the golden platform-web-starter problem reaches ApiError with its errors", async (context) => {
  context.mock.method(globalThis, "fetch", async () =>
    new Response(JSON.stringify(golden), { status: golden.status, headers: { "Content-Type": "application/problem+json" } }),
  );
  const client = createApiClient({ baseUrl: "https://example.test" });

  await assert.rejects(client.post("/orders", {}), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.status, 400);
    assert.equal(error.message, golden.detail);
    assert.deepEqual(error.problem, golden);
    assert.deepEqual(
      error.problem.errors.map((field) => field.pointer),
      ["#/items/0/quantity", "#/name"],
    );
    return true;
  });
});
