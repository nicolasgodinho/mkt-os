import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { parseSupabaseStatusEnv, type PublicSupabaseConfig } from './local-status';

/**
 * Asks the local Supabase CLI for the public connection settings. Used only when
 * NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY are not configured (local
 * development and CI). Returns null when no local stack is running; deployed environments
 * always configure the variables explicitly.
 */
export function discoverLocalSupabase(repoRoot: string): PublicSupabaseConfig | null {
  const isWindows = process.platform === 'win32';
  const cli = path.join(repoRoot, 'node_modules', '.bin', isWindows ? 'supabase.CMD' : 'supabase');
  try {
    const output = execFileSync(cli, ['status', '-o', 'env', '--workdir', repoRoot], {
      encoding: 'utf8',
      timeout: 20_000,
      stdio: ['ignore', 'pipe', 'ignore'],
      shell: isWindows,
    });
    return parseSupabaseStatusEnv(output);
  } catch {
    // No local stack (e.g. no Docker): authentication stays unconfigured, which the app reports.
    return null;
  }
}
