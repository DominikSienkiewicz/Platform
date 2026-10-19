// Testy własności (fast-check) kontraktu createApiClient: nagłówki w każdej postaci HeadersInit, mapowanie
// błędów HTTP na ApiError i reguła CSRF dla SPA — na losowych wejściach zamiast kilku wybranych przykładów.
// Plik ma rozszerzenie .js, bo OpenSSF Scorecard (check Fuzzing) szuka importu fast-check tylko w *.js i *.ts.
import assert from "node:assert/strict";
import test from "node:test";
import fc from "fast-check";
import { ApiError, createApiClient } from "../index.js";

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS", "TRACE"]);

const headerName = fc.stringMatching(/^[a-z][a-z0-9-]{0,15}$/).filter((name) => name !== "content-type");
const headerValue = fc.stringMatching(/^[A-Za-z0-9]([A-Za-z0-9 ._~:/=+-]{0,30}[A-Za-z0-9])?$/);
const headerEntries = fc.uniqueArray(fc.tuple(headerName, headerValue), { selector: ([name]) => name, maxLength: 8 });
const nonEmptyText = fc.stringMatching(/^[A-Za-z0-9][A-Za-z0-9 .,]{0,30}$/);

function recordFetch(context, respond) {
  const calls = [];
  context.mock.method(globalThis, "fetch", async (url, init) => {
    calls.push({ url, method: init.method, headers: new Headers(init.headers) });
    return respond();
  });
  return calls;
}

// Atrapa `document` z ciasteczkami, które każda iteracja ustawia od nowa.
function fakeDocument(context) {
  const fake = { cookie: "" };
  const previous = Object.getOwnPropertyDescriptor(globalThis, "document");
  Object.defineProperty(globalThis, "document", { value: fake, configurable: true });
  context.after(() => {
    if (previous) Object.defineProperty(globalThis, "document", previous);
    else delete globalThis.document;
  });
  return fake;
}

test("headers reach fetch the same as a record, a Headers instance or pairs, next to the JSON default", async (context) => {
  const calls = recordFetch(context, () => new Response(null, { status: 204 }));
  const client = createApiClient({ baseUrl: "https://example.test" });

  await fc.assert(
    fc.asyncProperty(headerEntries, async (entries) => {
      calls.length = 0;
      for (const headers of [Object.fromEntries(entries), new Headers(entries), entries]) {
        await client.get("/x", { headers });
      }
      for (const { headers } of calls) {
        assert.equal(headers.get("content-type"), "application/json");
        for (const [name, value] of entries) assert.equal(headers.get(name), value);
        assert.equal([...headers.keys()].length, entries.length + 1);
      }
    }),
  );
});

test("every 4xx and 5xx rejects with ApiError, its status, and the first of detail, message, title, status text", async (context) => {
  let response = new Response(null, { status: 204 });
  recordFetch(context, () => response);
  const client = createApiClient({ baseUrl: "https://example.test" });
  const problemField = fc.option(fc.oneof(nonEmptyText, fc.constant("")), { nil: undefined });

  await fc.assert(
    fc.asyncProperty(
      fc.integer({ min: 400, max: 599 }),
      fc.option(nonEmptyText, { nil: "" }),
      fc.record({ detail: problemField, message: problemField, title: problemField }),
      async (status, statusText, fields) => {
        const body = Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined));
        response = new Response(JSON.stringify(body), {
          status,
          statusText,
          headers: { "Content-Type": "application/problem+json" },
        });
        const expected =
          [body.detail, body.message, body.title].find((value) => typeof value === "string" && value) ??
          (statusText || `HTTP ${status}`);

        const error = await client.get("/x").then(
          () => assert.fail(`HTTP ${status} must reject`),
          (rejection) => rejection,
        );
        assert.ok(error instanceof ApiError);
        assert.equal(error.status, status);
        assert.equal(error.message, expected);
        assert.deepEqual(error.problem, { status, ...body });
      },
    ),
  );
});

test("xsrf echoes the cookie only on unsafe methods, and a header the call sets always wins", async (context) => {
  const calls = recordFetch(context, () => new Response(null, { status: 204 }));
  const page = fakeDocument(context);
  const client = createApiClient({ baseUrl: "https://example.test", xsrf: true });
  const method = fc
    .tuple(fc.constantFrom(...SAFE_METHODS, "POST", "PUT", "PATCH", "DELETE"), fc.boolean())
    .map(([name, lower]) => (lower ? name.toLowerCase() : name));
  const token = fc.stringMatching(/^[A-Za-z0-9]{1,16}$/);

  await fc.assert(
    fc.asyncProperty(
      method,
      fc.option(token, { nil: null }),
      fc.option(token, { nil: null }),
      async (verb, cookie, explicit) => {
        calls.length = 0;
        page.cookie = cookie === null ? "theme=dark" : `theme=dark; XSRF-TOKEN=${cookie}`;
        await client.request("/x", { method: verb, headers: explicit === null ? {} : { "X-XSRF-TOKEN": explicit } });

        const unsafe = !SAFE_METHODS.has(verb.toUpperCase());
        const expected = explicit ?? (unsafe ? cookie : null);
        assert.equal(calls[0].headers.get("X-XSRF-TOKEN"), expected);
      },
    ),
  );
});
