#!/usr/bin/env node
/**
 * `pnpm verify` — the single authoritative verification command (docs/11 "CI command contract").
 *
 * Runs every gate in order and stops at the first failure. CI runs the same command with
 * JMOS_DB_MODE=supabase, so database gates execute against the real Supabase stack.
 */
import { spawnSync } from 'node:child_process';

const steps = [
  ['format', 'pnpm -s format:check'],
  ['lint', 'pnpm -s lint'],
  ['typecheck', 'pnpm -s typecheck'],
  ['contracts', 'pnpm -s contracts:check'],
  ['unit', 'pnpm -s test:unit'],
  ['db: migrations + pgTAP (RLS, queue, protected acceptance SQL)', 'pnpm -s db:test'],
  ['acceptance (protected, TS)', 'pnpm -s test:acceptance'],
  ['integration (worker <-> Postgres)', 'pnpm -s test:integration'],
  ['build', 'pnpm -s build'],
  ['e2e', 'pnpm -s test:e2e'],
];

const results = [];
let failed = false;

for (const [name, command] of steps) {
  console.log(`\n━━ verify: ${name} ━━  (${command})`);
  const started = Date.now();
  const { status, error } = spawnSync(command, { stdio: 'inherit', shell: true });
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  const ok = status === 0 && !error;
  results.push({ name, ok, seconds });
  if (!ok) {
    failed = true;
    if (error) console.error(error);
    break;
  }
}

console.log('\n━━ verify summary ━━');
for (const { name, ok, seconds } of results) {
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}  (${seconds}s)`);
}
for (const [name] of steps.slice(results.length)) console.log(`  SKIP  ${name}  (not reached)`);
console.log(`  database mode: ${process.env.JMOS_DB_MODE ?? 'auto'}`);

process.exit(failed ? 1 : 0);
