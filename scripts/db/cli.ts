/**
 * Database harness: migrations from an empty database, pgTAP suites (DB/RLS + protected
 * acceptance SQL), and a database for worker integration tests.
 *
 * Modes (JMOS_DB_MODE):
 *   supabase  Real Supabase local stack. AUTHORITATIVE. Required in CI. Needs Docker and a running
 *             stack (`pnpm exec supabase start`, or `supabase db start` for the database only).
 *   pglite    In-process Postgres (WASM) with a minimal Supabase compat bootstrap. Developer
 *             fallback when Docker is unavailable. Not authoritative: session-level concurrency
 *             (e.g. SKIP LOCKED between two workers) is only exercised in supabase mode.
 *   auto      Default. Uses supabase if its database answers, otherwise pglite with a warning.
 *
 * Commands:
 *   reset        Apply migrations + seed to an empty database.
 *   test         reset, then run pgTAP suites: supabase/tests/database and tests/acceptance.
 *   serve        reset, then expose the PGlite database on 127.0.0.1 (pglite mode only).
 *   integration  Run worker integration tests (pytest -m integration) against a real
 *                Postgres wire connection.
 */
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { createServer } from 'node:net';
import { join, relative } from 'node:path';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { parseTap, tapProblems } from './tap';
import {
  canConnect,
  createPgliteDatabase,
  describeError,
  pgliteTarget,
  postgresTarget,
  redact,
  REPO_ROOT,
  supabaseDbUrl,
  type SqlTarget,
} from './targets';

// Optional local configuration (git-ignored). See .env.example.
const LOCAL_ENV = join(REPO_ROOT, '.env.local');
if (existsSync(LOCAL_ENV)) process.loadEnvFile(LOCAL_ENV);

type Mode = 'supabase' | 'pglite';

const SUITES = [
  { name: 'database', dir: join(REPO_ROOT, 'supabase/tests/database') },
  { name: 'acceptance (protected)', dir: join(REPO_ROOT, 'tests/acceptance') },
];

/** Local-only worker credentials set by supabase/seed.sql. */
const LOCAL_WORKER_PASSWORD = 'jmos-worker-local-dev-only';

async function resolveMode(): Promise<Mode> {
  const requested = process.env.JMOS_DB_MODE ?? 'auto';
  if (requested === 'supabase' || requested === 'pglite') return requested;
  if (requested !== 'auto') {
    throw new Error(`JMOS_DB_MODE must be supabase, pglite or auto (got "${requested}")`);
  }
  return (await canConnect(supabaseDbUrl())) ? 'supabase' : 'pglite';
}

function banner(mode: Mode): void {
  if (mode === 'supabase') {
    console.log('[db] mode: supabase (real local stack, authoritative)');
  } else {
    console.warn(
      '[db] mode: pglite — Postgres WASM + Supabase compat bootstrap.\n' +
        '[db] NOT authoritative: CI re-runs everything against real Supabase (JMOS_DB_MODE=supabase).',
    );
  }
}

function run(command: string, args: string[], env: NodeJS.ProcessEnv = {}): Promise<void> {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd: REPO_ROOT,
      stdio: 'inherit',
      shell: process.platform === 'win32',
      env: { ...process.env, ...env },
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolvePromise();
      else reject(new Error(`${command} ${args.join(' ')} exited with code ${String(code)}`));
    });
  });
}

async function resetSupabase(): Promise<void> {
  if (!(await canConnect(supabaseDbUrl()))) {
    throw new Error(
      `Supabase database is not reachable at ${redact(supabaseDbUrl())}. Start it with ` +
        '`pnpm exec supabase start` (requires Docker).',
    );
  }
  await run('supabase', ['db', 'reset', '--local']);
}

async function listTestFiles(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { recursive: true, withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith('.test.sql'))
    .map((entry) => join(entry.parentPath, entry.name))
    .sort();
}

async function runSuites(target: SqlTarget): Promise<boolean> {
  let ok = true;
  for (const suite of SUITES) {
    const files = await listTestFiles(suite.dir);
    console.log(`\n[db] suite ${suite.name}: ${String(files.length)} file(s)`);
    for (const file of files) {
      const name = relative(REPO_ROOT, file);
      let problems: string[];
      let passed = 0;
      try {
        const report = parseTap(await target.exec(await readFile(file, 'utf8')));
        problems = tapProblems(report);
        passed = report.passed;
        for (const line of report.diagnostics) console.log(`      ${line}`);
      } catch (error) {
        problems = [`SQL error: ${describeError(error)}`];
        // Leave the session usable for the next file; a failure here is reported, not hidden.
        await target.exec('rollback');
      }
      if (problems.length === 0) {
        console.log(`  PASS ${name} (${String(passed)} assertions)`);
      } else {
        ok = false;
        console.error(`  FAIL ${name}`);
        for (const problem of problems) console.error(`       ${problem}`);
      }
    }
  }
  return ok;
}

async function freePort(): Promise<number> {
  return new Promise((resolvePromise, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() => {
        if (address !== null && typeof address === 'object') resolvePromise(address.port);
        else reject(new Error('could not allocate a local port'));
      });
    });
  });
}

async function startPgliteServer(port: number): Promise<{ stop: () => Promise<void> }> {
  const db = await createPgliteDatabase();
  const server = new PGLiteSocketServer({ db, port, host: '127.0.0.1', maxConnections: 16 });
  await server.start();
  return {
    async stop() {
      await server.stop();
      await db.close();
    },
  };
}

async function main(): Promise<void> {
  const command = process.argv[2];
  const mode = await resolveMode();
  banner(mode);

  switch (command) {
    case 'reset': {
      if (mode === 'supabase') {
        await resetSupabase();
      } else {
        const db = await createPgliteDatabase();
        await db.close();
        console.log('[db] migrations and seed applied to an empty PGlite database');
      }
      return;
    }

    case 'test': {
      let target: SqlTarget;
      if (mode === 'supabase') {
        await resetSupabase();
        target = await postgresTarget(supabaseDbUrl());
      } else {
        target = pgliteTarget(await createPgliteDatabase());
        console.log('[db] migrations and seed applied to an empty database');
      }
      console.log(`[db] target: ${target.label}`);
      try {
        const ok = await runSuites(target);
        if (!ok) process.exitCode = 1;
      } finally {
        await target.close();
      }
      return;
    }

    case 'serve': {
      if (mode !== 'pglite') {
        throw new Error('serve is only needed in pglite mode; Supabase already listens on 54322');
      }
      const port = Number(process.env.JMOS_PGLITE_PORT ?? 54329);
      const server = await startPgliteServer(port);
      console.log(
        `[db] PGlite listening on postgresql://postgres@127.0.0.1:${String(port)}/postgres`,
      );
      const shutdown = () => {
        void server.stop().then(() => process.exit(0));
      };
      process.on('SIGINT', shutdown);
      process.on('SIGTERM', shutdown);
      return;
    }

    case 'integration': {
      const pytest = [
        'scripts/py.mjs',
        '-m',
        'pytest',
        '-m',
        'integration',
        'apps/ai-worker/tests',
      ];
      if (mode === 'supabase') {
        const workerUrl = new URL(supabaseDbUrl());
        workerUrl.username = 'jmos_worker';
        workerUrl.password = LOCAL_WORKER_PASSWORD;
        await run('node', pytest, {
          JMOS_TEST_DB_MODE: 'supabase',
          JMOS_TEST_ADMIN_DATABASE_URL: supabaseDbUrl(),
          JMOS_TEST_WORKER_DATABASE_URL: workerUrl.toString(),
        });
        return;
      }
      const port = await freePort();
      const server = await startPgliteServer(port);
      const url = `postgresql://postgres@127.0.0.1:${String(port)}/postgres`;
      try {
        await run('node', pytest, {
          JMOS_TEST_DB_MODE: 'pglite',
          JMOS_TEST_ADMIN_DATABASE_URL: url,
          // PGlite has a single superuser session, so role separation is covered by pgTAP.
          JMOS_TEST_WORKER_DATABASE_URL: url,
        });
      } finally {
        await server.stop();
      }
      return;
    }

    default:
      throw new Error('usage: tsx scripts/db/cli.ts <reset|test|serve|integration>');
  }
}

main().catch((error: unknown) => {
  console.error(`[db] ${describeError(error)}`);
  process.exitCode = 1;
});
