import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  eslint: { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
  experimental: {
    serverActions: {
      // Employee photos are compressed client-side (~<1 MB), but this leaves safe headroom.
      bodySizeLimit: "10mb",
    },
  },
  // Ensure Prisma engines make it into the standalone bundle used on the VPS.
  outputFileTracingIncludes: {
    "/*": [
      "./node_modules/.prisma/client/**/*",
      "./node_modules/@prisma/client/**/*",
    ],
  },
};

export default nextConfig;
