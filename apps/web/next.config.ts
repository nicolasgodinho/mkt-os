import path from 'node:path';
import type { NextConfig } from 'next';
import { discoverLocalSupabase } from './src/lib/supabase/local-discovery';

// Scripts always run with apps/web as the working directory.
const repoRoot = path.resolve(process.cwd(), '../..');

const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];

// Public Supabase settings: explicit env vars win (every deployed environment sets them). Without
// them, the local stack is discovered through the Supabase CLI (development and CI only).
const explicitlyConfigured =
  process.env.NEXT_PUBLIC_SUPABASE_URL !== undefined &&
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY !== undefined;
const local = explicitlyConfigured ? null : discoverLocalSupabase(repoRoot);

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // Workspace packages are consumed as TypeScript source.
  transpilePackages: ['@jmos/ui'],
  turbopack: { root: repoRoot },
  ...(local === null
    ? {}
    : {
        env: {
          NEXT_PUBLIC_SUPABASE_URL: local.url,
          NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: local.publicKey,
        },
      }),
  headers() {
    return Promise.resolve([
      { source: '/:path*', headers: securityHeaders },
      {
        source: '/convite/:path*',
        headers: [
          { key: 'Referrer-Policy', value: 'no-referrer' },
          { key: 'Cache-Control', value: 'no-store' },
        ],
      },
      {
        source: '/auth/:path*',
        headers: [
          { key: 'Referrer-Policy', value: 'no-referrer' },
          { key: 'Cache-Control', value: 'no-store' },
        ],
      },
    ]);
  },
};

export default nextConfig;
