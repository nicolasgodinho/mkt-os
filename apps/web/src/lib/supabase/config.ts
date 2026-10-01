import type { PublicSupabaseConfig } from './local-status';

/**
 * Public Supabase settings for the web app, or null when authentication is not configured in this
 * environment. The web app only ever uses the public (publishable/anon) key together with the
 * signed-in user's session: row level security decides what each request may see. It never uses a
 * service-role key.
 */
export function getSupabaseConfig(): PublicSupabaseConfig | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publicKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (url === undefined || url === '' || publicKey === undefined || publicKey === '') return null;
  return { url, publicKey };
}
