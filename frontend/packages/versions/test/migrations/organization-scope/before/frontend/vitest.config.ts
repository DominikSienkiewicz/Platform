import { defineConfig, mergeConfig } from "vitest/config";
import { baseConfig } from "@dominiksienkiewicz/vitest-config";

export default mergeConfig(baseConfig, defineConfig({}));
