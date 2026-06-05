// Rozszerza `expect` Vitesta o matchery jest-dom (toBeInTheDocument, toHaveAttribute, ...)
import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";

// Czyści DOM między testami (RTL nie robi tego automatycznie poza auto-cleanup).
afterEach(() => {
  cleanup();
});
