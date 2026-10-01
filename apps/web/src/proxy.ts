import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { getSupabaseConfig } from '@/lib/supabase/config';

/**
 * Refreshes the Supabase session on every request so Server Components see a valid token.
 * This is NOT an authorization layer: access is decided in the data layer and, ultimately, by
 * row level security in Postgres (docs/05 §1).
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const supabaseConfig = getSupabaseConfig();
  if (supabaseConfig === null) return response;

  const supabase = createServerClient(supabaseConfig.url, supabaseConfig.publicKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (cookiesToSet, headers) => {
        for (const { name, value } of cookiesToSet) request.cookies.set(name, value);
        response = NextResponse.next({ request });
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
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api/health).*)'],
};
