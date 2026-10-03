import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { buildCsp, createNonce, NONCE_HEADER } from '@/lib/security/csp';
import { getSupabaseConfig } from '@/lib/supabase/config';

/**
 * Per request: sets the nonce-based Content-Security-Policy and refreshes the Supabase session so
 * Server Components see a valid token. This is NOT an authorization layer: access is decided in
 * the data layer and, ultimately, by row level security in Postgres (docs/05 §1).
 */
export async function proxy(request: NextRequest) {
  const supabaseConfig = getSupabaseConfig();
  const nonce = createNonce();
  const csp = buildCsp({
    nonce,
    supabaseUrl: supabaseConfig?.url ?? null,
    development: process.env.NODE_ENV === 'development',
  });

  // Next.js reads the policy (and the nonce in it) from the request headers to tag its scripts.
  const forward = () => {
    const headers = new Headers(request.headers);
    headers.set(NONCE_HEADER, nonce);
    headers.set('Content-Security-Policy', csp);
    return NextResponse.next({ request: { headers } });
  };

  let response = forward();
  if (supabaseConfig !== null) {
    const supabase = createServerClient(supabaseConfig.url, supabaseConfig.publicKey, {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookiesToSet, headers) => {
          for (const { name, value } of cookiesToSet) request.cookies.set(name, value);
          response = forward();
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
          // Responses carrying session cookies must never be cached by a CDN or proxy.
          for (const [key, value] of Object.entries(headers)) response.headers.set(key, value);
        },
      },
    });

    // Validates the token with Supabase Auth and refreshes it when expired.
    await supabase.auth.getUser();
  }
  response.headers.set('Content-Security-Policy', csp);
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api/health).*)'],
};
