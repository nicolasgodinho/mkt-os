/**
 * Parses `supabase status -o env` output from the LOCAL development stack.
 *
 * Only the API URL and the public client key (publishable or legacy anon) are ever returned.
 * Server-only secrets printed by the CLI (service role key, secret key, JWT secret, database URL)
 * are deliberately ignored: they must never reach a browser bundle.
 */
export interface PublicSupabaseConfig {
  inbucketUrl?: string;
  url: string;
  publicKey: string;
}

const LINE = /^([A-Z0-9_]+)=(?:"([^"]*)"|(\S*))$/;

export function parseSupabaseStatusEnv(output: string): PublicSupabaseConfig | null {
  const values = new Map<string, string>();
  for (const raw of output.split(/\r?\n/)) {
    const match = LINE.exec(raw.trim());
    if (match?.[1] !== undefined) values.set(match[1], match[2] ?? match[3] ?? '');
  }
  const url = values.get('API_URL');
  const inbucketUrl = values.get('INBUCKET_URL');
  const publicKey = values.get('PUBLISHABLE_KEY') ?? values.get('ANON_KEY');
  if (url === undefined || url === '' || publicKey === undefined || publicKey === '') return null;
  if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(url)) {
    // Discovery exists for the local stack only; anything else must be configured explicitly.
    return null;
  }
  return { url, publicKey, inbucketUrl };
}
