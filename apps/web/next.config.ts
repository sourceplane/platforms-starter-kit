import type { NextConfig } from "next";
import path from "node:path";
import { initOpenNextCloudflareForDev } from "@opennextjs/cloudflare";

// `next dev` reaches the Worker's bindings (the KV namespace declared in
// wrangler.jsonc — run `pnpm run wire:fixture` first) through wrangler's
// platform proxy, so `getCloudflareContext()` works outside the Worker too.
initOpenNextCloudflareForDev();

const nextConfig: NextConfig = {
  /* config options here */
  experimental: {
    // Enable experimental features if needed
  },
  // Required by @opennextjs/cloudflare, which bundles `.next/standalone/**`
  // into the Worker. Trace from the monorepo root so workspace dependencies
  // resolve from the root node_modules.
  output: "standalone",
  outputFileTracingRoot: path.join(__dirname, "../.."),
};

export default nextConfig;
