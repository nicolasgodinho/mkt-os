import path from 'node:path';
import { expect, type Page, test } from '@playwright/test';
import { discoverLocalSupabase } from '../../../apps/web/src/lib/supabase/local-discovery';
import type { PublicSupabaseConfig } from '../../../apps/web/src/lib/supabase/local-status';
export type { PublicSupabaseConfig };

const REPO_ROOT = path.resolve(import.meta.dirname, '../../..');

/** Deterministic identities and ids from supabase/seed.sql (local/CI only). */
export const SEED = {
  password: 'jmos-local-dev-password',
  users: {
    admin: 'admin@jansen.local',
    strategist: 'strategist@jansen.local',
    contributor: 'contributor@jansen.local',
    revokedInternal: 'revoked@jansen.local',
    clientAdminA: 'client-admin@cliente-a.local',
    approverA: 'approver@cliente-a.local',
    collaboratorA: 'collaborator@cliente-a.local',
    revokedClientA: 'revoked@cliente-a.local',
    viewerB: 'viewer@cliente-b.local',
    otherAdmin: 'admin@outra-agencia.local',
  },
  workspaces: { jansen: 'jansen', other: 'outra-agencia' },
  workspaceIds: { jansen: '10000000-0000-4000-8000-000000000001' },
  clients: {
    a: '20000000-0000-4000-8000-00000000000a',
    b: '20000000-0000-4000-8000-00000000000b',
    c: '20000000-0000-4000-8000-00000000000c',
  },
  randomId: '0d0d0d0d-0000-4000-8000-00000000dead',
} as const;

let discovered: PublicSupabaseConfig | null | undefined;

function supabaseConfig(): PublicSupabaseConfig | null {
  discovered ??= discoverLocalSupabase(REPO_ROOT);
  return discovered;
}

/**
 * Authenticated specs need the real Supabase stack. Locally without Docker they are skipped with
 * a reason; in CI (JMOS_DB_MODE=supabase) a missing stack is a failure, never a skip.
 */
export function requireSupabase(): PublicSupabaseConfig {
  const config = supabaseConfig();
  if (config === null && process.env.JMOS_DB_MODE === 'supabase') {
    throw new Error('JMOS_DB_MODE=supabase but the local Supabase stack is not reachable');
  }
  test.skip(config === null, 'needs the real Supabase stack (Auth + PostgREST); runs in CI');
  if (config === null) throw new Error('unreachable: skipped above');
  return config;
}

export async function login(page: Page, email: string): Promise<void> {
  await page.goto('/login');
  await page.getByLabel('E-mail').fill(email);
  await page.getByLabel('Senha').fill(SEED.password);
  await page.getByRole('button', { name: 'Entrar' }).click();
  await expect(page).not.toHaveURL(/\/login/);
}

export async function logout(page: Page): Promise<void> {
  await page.getByRole('button', { name: 'Sair' }).click();
  await expect(page).toHaveURL(/\/login/);
}

export async function expectNotFound(page: Page, url: string): Promise<void> {
  await page.goto(url);
  await expect(page.getByRole('heading', { name: 'Página não encontrada' })).toBeVisible();
}

export interface ApiResult {
  status: number;
  /** Postgres SQLSTATE (e.g. 42501, P0002) when the request failed. */
  code: string | undefined;
  message: string | undefined;
  data: unknown;
}

export interface Api {
  rpc(fn: string, args: Record<string, unknown>): Promise<ApiResult>;
  select(table: string, columns: string): Promise<ApiResult>;
  update(table: string, values: Record<string, unknown>, id: string): Promise<ApiResult>;
}

async function toResult(response: Response): Promise<ApiResult> {
  const text = await response.text();
  const body: unknown = text === '' ? null : JSON.parse(text);
  if (response.ok)
    return { status: response.status, code: undefined, message: undefined, data: body };
  const error = (body ?? {}) as { code?: string; message?: string };
  return { status: response.status, code: error.code, message: error.message, data: null };
}

/**
 * Raw HTTP access to PostgREST with the public key and, optionally, a user's access token: exactly
 * what a browser (or an attacker holding a valid account) can send.
 */
function api(config: PublicSupabaseConfig, accessToken: string | null): Api {
  const headers: Record<string, string> = {
    apikey: config.publicKey,
    'Content-Type': 'application/json',
    ...(accessToken === null ? {} : { Authorization: `Bearer ${accessToken}` }),
  };
  const rest = `${config.url}/rest/v1`;
  return {
    async rpc(fn, args) {
      return toResult(
        await fetch(`${rest}/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args) }),
      );
    },
    async select(table, columns) {
      return toResult(await fetch(`${rest}/${table}?select=${columns}`, { headers }));
    },
    async update(table, values, id) {
      return toResult(
        await fetch(`${rest}/${table}?id=eq.${id}`, {
          method: 'PATCH',
          headers,
          body: JSON.stringify(values),
        }),
      );
    },
  };
}

/** Signs in a seeded identity through Supabase Auth and returns its PostgREST access. */
export async function apiAs(config: PublicSupabaseConfig, email: string): Promise<Api> {
  const response = await fetch(`${config.url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: config.publicKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: SEED.password }),
  });
  const body = (await response.json()) as { access_token?: string };
  if (!response.ok || body.access_token === undefined) {
    throw new Error(`sign-in failed for ${email} (HTTP ${String(response.status)})`);
  }
  return api(config, body.access_token);
}

export function anonymousApi(config: PublicSupabaseConfig): Api {
  return api(config, null);
}

// Local mail catcher of the Supabase stack (Mailpit, `[inbucket] port` in supabase/config.toml).
const MAIL_API = 'http://127.0.0.1:54324/api/v1';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

async function latestMessageText(email: string): Promise<string | null> {
  const search = await fetch(`${MAIL_API}/search?query=${encodeURIComponent(`to:"${email}"`)}`);
  if (!search.ok) throw new Error(`mail catcher search failed: ${String(search.status)}`);
  const found: unknown = await search.json();
  const messages = isRecord(found) && Array.isArray(found.messages) ? found.messages : [];
  const first: unknown = messages[0];
  if (!isRecord(first) || typeof first.ID !== 'string') return null;
  const response = await fetch(`${MAIL_API}/message/${encodeURIComponent(first.ID)}`);
  if (!response.ok) throw new Error(`mail catcher read failed: ${String(response.status)}`);
  const message: unknown = await response.json();
  if (!isRecord(message)) return null;
  const text = typeof message.Text === 'string' ? message.Text : '';
  const html = typeof message.HTML === 'string' ? message.HTML : '';
  return `${text}
${html}`;
}

/** The sign-in link from the newest e-mail sent to `email` (waits up to 15 s for it to arrive). */
export async function getEmailLink(email: string): Promise<string> {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const body = await latestMessageText(email);
    const match = body
      ? /https?:\/\/[^\s"'<>]+(?:auth\/v1\/verify|auth\/confirm)[^\s"'<>]*/.exec(body)
      : null;
    if (match) return match[0].replaceAll('&amp;', '&');
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`no sign-in link was e-mailed to ${email}`);
}
