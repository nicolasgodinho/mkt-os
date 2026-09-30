#!/usr/bin/env node
/**
 * Runs Python tooling from the AI Worker's virtualenv (apps/ai-worker/.venv), cross-platform.
 *
 *   node scripts/py.mjs --setup        create the venv and install the worker with dev extras
 *   node scripts/py.mjs -m pytest ...  run a module with the venv interpreter
 *
 * The bootstrap interpreter for --setup comes from JMOS_PYTHON, or `python3`/`python` on PATH.
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '..');
const workerDir = join(repoRoot, 'apps/ai-worker');
const venvDir = join(workerDir, '.venv');
const venvPython =
  process.platform === 'win32'
    ? join(venvDir, 'Scripts', 'python.exe')
    : join(venvDir, 'bin', 'python');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  return result.status ?? 1;
}

function bootstrapPython() {
  const candidates = process.env.JMOS_PYTHON
    ? [process.env.JMOS_PYTHON]
    : process.platform === 'win32'
      ? ['python', 'py']
      : ['python3', 'python'];
  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ['-c', 'import sys; assert sys.version_info >= (3, 12)']);
    if (probe.status === 0) return candidate;
  }
  throw new Error('Python >= 3.12 not found. Install it or set JMOS_PYTHON.');
}

// Optional local configuration (git-ignored). See .env.example.
const localEnv = join(repoRoot, '.env.local');
if (existsSync(localEnv)) process.loadEnvFile(localEnv);

const args = process.argv.slice(2);

if (args[0] === '--setup') {
  if (!existsSync(venvPython)) {
    const status = run(bootstrapPython(), ['-m', 'venv', venvDir]);
    if (status !== 0) process.exit(status);
  }
  process.exit(
    run(venvPython, ['-m', 'pip', 'install', '--disable-pip-version-check', '-e', '.[dev]'], {
      cwd: workerDir,
    }),
  );
}

if (!existsSync(venvPython)) {
  console.error('AI Worker virtualenv not found. Run `pnpm setup:py` first.');
  process.exit(1);
}
process.exit(run(venvPython, args));
