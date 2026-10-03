/**
 * Content-Security-Policy for every page (docs/05 §3: the browser is untrusted ground).
 *
 * Scripts run only with the per-request nonce (`'strict-dynamic'` lets those scripts load the
 * chunks they need), so injected markup cannot execute code. Next.js reads the nonce from this
 * header and applies it to its own scripts; pages render dynamically, which they already do
 * because every page checks the session.
 */

export interface CspOptions {
  nonce: string;
  /** Supabase origin the browser may call (auth refresh); null when auth is not configured. */
  supabaseUrl: string | null;
  /** Next.js development needs eval for fast refresh and a websocket for HMR. */
  development: boolean;
}

export const NONCE_HEADER = 'x-nonce';

/** A fresh base64 nonce (128 bits) for one request. */
export function createNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function origin(url: string | null): string | null {
  if (url === null) return null;
  try {
    return new URL(url).origin;
  } catch {
    // A malformed URL is a configuration error elsewhere; the policy just leaves it out.
    return null;
  }
}

export function buildCsp({ nonce, supabaseUrl, development }: CspOptions): string {
  const supabase = origin(supabaseUrl);
  const directives: Record<string, string[]> = {
    'default-src': ["'self'"],
    'script-src': [
      "'self'",
      `'nonce-${nonce}'`,
      "'strict-dynamic'",
      ...(development ? ["'unsafe-eval'"] : []),
    ],
    // React and Tailwind set inline style attributes; styles cannot execute code.
    'style-src': ["'self'", "'unsafe-inline'"],
    'img-src': ["'self'", 'data:', 'blob:'],
    'font-src': ["'self'", 'data:'],
    'connect-src': [
      "'self'",
      ...(supabase === null ? [] : [supabase]),
      ...(development ? ['ws:'] : []),
    ],
    'frame-src': ["'none'"],
    'frame-ancestors': ["'none'"],
    'object-src': ["'none'"],
    'base-uri': ["'self'"],
    'form-action': ["'self'"],
  };
  // No `upgrade-insecure-requests`: HTTPS is enforced by the host and HSTS, and the policy must
  // also work for the production build served over plain HTTP on loopback (E2E).
  return Object.entries(directives)
    .map(([name, values]) => `${name} ${values.join(' ')}`)
    .join('; ');
}
