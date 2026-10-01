import 'server-only';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { getSupabaseConfig } from './config';

/**
 * Supabase client bound to the current request's session, for Server Components.
 *
 * Server Components cannot write cookies, so session refreshes are persisted by `proxy.ts`,
 * which runs first on every request. Cookie writes here are intentionally not attempted.
 */
export async function createSupabaseReader() {
  // Read cookies first: session-dependent pages must always render per request, even in an
  // environment where authentication is not configured.
  const cookieStore = await cookies();
  const config = getSupabaseConfig();
  if (config === null) return null;
  return createServerClient(config.url, config.publicKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: () => undefined,
    },
  });
}

/** Supabase client that may write session cookies, for Server Actions only. */
export async function createSupabaseWriter() {
  const cookieStore = await cookies();
  const config = getSupabaseConfig();
  if (config === null) return null;
  return createServerClient(config.url, config.publicKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (cookiesToSet) => {
        for (const { name, value, options } of cookiesToSet) cookieStore.set(name, value, options);
      },
    },
  });
}
