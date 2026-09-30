/**
 * Protected-authority policy for pull requests (docs/11 "Protected paths", docs/12 "Protected
 * authority", AGENTS.md). Pure logic with no dependencies, so CI can run the base branch's copy.
 *
 * A pull request fails when it:
 *   - changes /tests/acceptance without the `authority:TEST_SPEC` label;
 *   - changes /docs, AGENTS.md, CI workflows or this policy without `authority:ARCHITECTURE_CHANGE`;
 *   - modifies, renames or deletes an existing migration (migrations are append-only);
 *   - adds a migration that is misnamed or sorts before an existing migration.
 *
 * Labels are applied by humans. This check makes protected changes visible and deliberate;
 * branch protection plus required reviewers decide who may approve them.
 */

export interface FileChange {
  /** git status letter: A, M, D, R (rename), C (copy), T (type change). */
  status: string;
  path: string;
  /** Original path for renames/copies. */
  fromPath?: string;
}

export const AUTHORITY_RULES = [
  { label: 'authority:TEST_SPEC', prefixes: ['tests/acceptance/'] },
  {
    label: 'authority:ARCHITECTURE_CHANGE',
    prefixes: ['docs/', 'AGENTS.md', '.github/workflows/', 'scripts/ci/'],
  },
] as const;

const MIGRATIONS_DIR = 'supabase/migrations/';
const MIGRATION_NAME = /^\d{14}_[a-z0-9_]+\.sql$/;

export function parseNameStatus(output: string): FileChange[] {
  return output
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => {
      const [status = '', first = '', second] = line.split('\t');
      const letter = status.charAt(0);
      return second === undefined
        ? { status: letter, path: first }
        : { status: letter, path: second, fromPath: first };
    });
}

export function evaluateChanges(
  changes: readonly FileChange[],
  labels: readonly string[],
  baseMigrations: readonly string[],
): string[] {
  const problems: string[] = [];

  for (const rule of AUTHORITY_RULES) {
    if (labels.includes(rule.label)) continue;
    const touched = changes
      .flatMap((change) => [change.path, change.fromPath])
      .filter((path): path is string => path !== undefined)
      .filter((path) => rule.prefixes.some((prefix) => path.startsWith(prefix)));
    for (const path of new Set(touched)) {
      problems.push(`${path} is protected; the change requires the "${rule.label}" label`);
    }
  }

  const latestBase = [...baseMigrations].sort().at(-1);
  for (const change of changes) {
    const paths = [change.path, change.fromPath].filter((p): p is string => p !== undefined);
    if (!paths.some((path) => path.startsWith(MIGRATIONS_DIR))) continue;

    if (change.status !== 'A') {
      problems.push(
        `${change.fromPath ?? change.path}: existing migrations are append-only ` +
          '(add a new migration instead of editing, renaming or deleting one)',
      );
      continue;
    }
    const name = change.path.slice(MIGRATIONS_DIR.length);
    if (!name.endsWith('.sql')) continue;
    if (!MIGRATION_NAME.test(name)) {
      problems.push(`${change.path}: migration names must match YYYYMMDDHHMMSS_snake_case.sql`);
    } else if (latestBase !== undefined && name <= latestBase) {
      problems.push(`${change.path}: new migrations must sort after ${latestBase}`);
    }
  }

  return problems;
}
