import { defineConfig, mergeConfig } from "vitest/config";
import { baseConfig } from "@seniordeveloper-pl-dominik-sienkiewicz/vitest-config";

export default mergeConfig(baseConfig, defineConfig({}));
