import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  cacheComponents: true,
  partialPrefetching: true,
  allowedDevOrigins: ["miniature-barnacle-r7w556vr6xgvhxvqj-3000.app.github.dev"],
  ...(process.env.NODE_ENV === "development"
    ? {
        experimental: {
          serverActions: {
            allowedOrigins: ["localhost:3000"],
          },
        },
      }
    : {}),
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
