// Copy to <repo>/frontend/next.config.ts. `standalone` makes `next build` emit .next/standalone with server.js
// and only the node_modules the server needs, which templates/Dockerfile.frontend copies into its runner stage.
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
};

export default nextConfig;
