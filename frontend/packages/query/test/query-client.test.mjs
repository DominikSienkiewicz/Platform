import assert from "node:assert/strict";
import { test } from "node:test";
import { createQueryClient } from "../index.js";

test("queries default to a 60 s stale time without refetching on window focus", () => {
  const queries = createQueryClient().getDefaultOptions().queries;
  assert.equal(queries.staleTime, 60_000);
  assert.equal(queries.refetchOnWindowFocus, false);
});

test("queries options override the defaults and keep the rest", () => {
  const queries = createQueryClient({ queries: { staleTime: 0, retry: 1 } }).getDefaultOptions().queries;
  assert.equal(queries.staleTime, 0);
  assert.equal(queries.retry, 1);
  assert.equal(queries.refetchOnWindowFocus, false);
});

test("defaultOptions sets other sections, such as mutations", () => {
  const options = createQueryClient({ defaultOptions: { mutations: { retry: 2 } } }).getDefaultOptions();
  assert.equal(options.mutations.retry, 2);
  assert.equal(options.queries.staleTime, 60_000);
});
