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
  // Production is HTTPS-only (browsers ignore HSTS over plain HTTP, e.g. the local E2E build).
  ...(process.env.NODE_ENV === 'production'
    ? [{ key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' }]
    : []),
];
// The Content-Security-Policy is per request (it carries a nonce): see src/proxy.ts.

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
    return Promise.resolve([{ source: '/:path*', headers: securityHeaders }]);
  },
};

export default nextConfig;
