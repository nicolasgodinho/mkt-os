/**
 * CI entry point for the protected-authority policy (see protected-paths.ts).
 * Env: BASE_SHA, HEAD_SHA, PR_LABELS (JSON array of label names).
 */
import { execFileSync } from 'node:child_process';
import { evaluateChanges, packageScriptsChanged, parseNameStatus } from './protected-paths';

function required(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === '') throw new Error(`${name} is required`);
  return value;
}

function git(args: string[]): string {
  return execFileSync('git', args, { encoding: 'utf8' });
}

/** File content at a commit. Only called for paths git reported as existing at that commit. */
function show(commit: string, path: string): string {
  return git(['show', `${commit}:${path}`]);
}

const base = required('BASE_SHA');
const head = required('HEAD_SHA');
const labels = JSON.parse(process.env.PR_LABELS ?? '[]') as unknown;
if (!Array.isArray(labels) || !labels.every((label) => typeof label === 'string')) {
  throw new Error('PR_LABELS must be a JSON array of strings');
}

const changes = parseNameStatus(git(['diff', '--name-status', '-M', `${base}...${head}`]));
// `base...head` diffs against the merge base, so "before" contents must come from it too.
const mergeBase = git(['merge-base', base, head]).trim();
const baseMigrations = git(['ls-tree', '--name-only', base, 'supabase/migrations/'])
  .split('\n')
  .map((path) => path.trim().replace('supabase/migrations/', ''))
  .filter((name) => name.endsWith('.sql'));

// Existing manifests only: a new package cannot weaken gates that already exist.
const manifestsWithChangedScripts = changes
  .filter((change) => change.status !== 'A')
  .filter((change) => (change.fromPath ?? change.path).split('/').at(-1) === 'package.json')
  .filter((change) =>
    packageScriptsChanged(
      show(mergeBase, change.fromPath ?? change.path),
      change.status === 'D' ? null : show(head, change.path),
    ),
  )
  .map((change) => change.fromPath ?? change.path);

const problems = evaluateChanges(changes, labels, baseMigrations, manifestsWithChangedScripts);
if (problems.length > 0) {
  console.error('Protected-authority check failed:');
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(`Protected-authority check passed (${String(changes.length)} changed file(s)).`);
