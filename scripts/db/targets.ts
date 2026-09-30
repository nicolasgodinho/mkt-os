import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { pgtap } from '@electric-sql/pglite-pgtap';
import pg from 'pg';

export const REPO_ROOT = resolve(import.meta.dirname, '../..');
export const MIGRATIONS_DIR = join(REPO_ROOT, 'supabase/migrations');
export const SEED_FILE = join(REPO_ROOT, 'supabase/seed.sql');
const COMPAT_FILE = join(REPO_ROOT, 'scripts/db/pglite-supabase-compat.sql');

/** Connection string of the Supabase local database (`supabase start`), overridable by JMOS_DB_URL. */
export function supabaseDbUrl(): string {
  return process.env.JMOS_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
}

/** One row set per SQL statement, as returned by a simple-protocol multi-statement query. */
export type StatementRows = readonly Record<string, unknown>[];

export interface SqlTarget {
  readonly label: string;
  /** Executes a multi-statement SQL script and returns the rows of every statement. */
  exec(sql: string): Promise<StatementRows[]>;
  close(): Promise<void>;
}

export async function listMigrations(): Promise<string[]> {
  const names = (await readdir(MIGRATIONS_DIR)).filter((name) => name.endsWith('.sql')).sort();
  return names.map((name) => join(MIGRATIONS_DIR, name));
}

/**
 * In-process Postgres (WASM) with the Supabase compat bootstrap, all migrations and the seed
 * applied: the same "from an empty database" path that `supabase db reset` runs.
 */
export async function createPgliteDatabase(): Promise<PGlite> {
  const db = await PGlite.create({ extensions: { pgtap } });
  // Supabase puts `extensions` on the search_path (pgTAP and other extensions live there).
  await db.exec(`set search_path = "$user", public, extensions;`);
  await db.exec(await readFile(COMPAT_FILE, 'utf8'));
  for (const file of await listMigrations()) {
    try {
      await db.exec(await readFile(file, 'utf8'));
    } catch (error) {
      throw new Error(`Migration failed: ${file}\n${describeError(error)}`, { cause: error });
    }
  }
  try {
    await db.exec(await readFile(SEED_FILE, 'utf8'));
  } catch (error) {
    throw new Error(`Seed failed: ${SEED_FILE}\n${describeError(error)}`, { cause: error });
  }
  return db;
}

export function pgliteTarget(db: PGlite): SqlTarget {
  return {
    label: 'PGlite (Postgres WASM + Supabase compat)',
    async exec(sql) {
      const results = await db.exec(sql);
      return results.map((result) => result.rows as StatementRows);
    },
    async close() {
      await db.close();
    },
  };
}

export async function postgresTarget(connectionString: string): Promise<SqlTarget> {
  const client = new pg.Client({ connectionString });
  await client.connect();
  return {
    label: `Postgres (${redact(connectionString)})`,
    async exec(sql) {
      // A multi-statement simple query resolves to one QueryResult per statement at runtime,
      // although pg's typings only describe the single-statement case.
      const result: unknown = await client.query<Record<string, unknown>>(sql);
      const results = (Array.isArray(result) ? result : [result]) as pg.QueryResult<
        Record<string, unknown>
      >[];
      return results.map((r) => r.rows);
    },
    async close() {
      await client.end();
    },
  };
}

/** True when a Postgres server answers at the URL within the timeout. */
export async function canConnect(connectionString: string, timeoutMs = 1500): Promise<boolean> {
  const client = new pg.Client({ connectionString, connectionTimeoutMillis: timeoutMs });
  try {
    await client.connect();
  } catch {
    // "Unreachable" is the expected answer when no local Supabase is running.
    return false;
  }
  try {
    await client.query('select 1');
    return true;
  } finally {
    await client.end();
  }
}

export function redact(connectionString: string): string {
  return connectionString.replace(/\/\/([^:/@]+):[^@]*@/, '//$1:***@');
}

export function describeError(error: unknown): string {
  if (error instanceof Error) {
    const detail = error as Error & { detail?: string; hint?: string };
    return [error.message, detail.detail, detail.hint].filter(Boolean).join('\n');
  }
  return String(error);
}
