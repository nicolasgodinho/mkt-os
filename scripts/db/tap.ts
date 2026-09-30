import type { StatementRows } from './targets';

export interface TapReport {
  planned: number | null;
  passed: number;
  failed: string[];
  diagnostics: string[];
}

const TAP_LINE = /^(?:(?:not )?ok \d+|1\.\.\d+|#)/;

/**
 * Extracts pgTAP output from the rows of a test script. pgTAP functions return TAP text as
 * single-column rows; failures carry multi-line diagnostics.
 */
export function parseTap(statements: StatementRows[]): TapReport {
  const report: TapReport = { planned: null, passed: 0, failed: [], diagnostics: [] };
  for (const rows of statements) {
    for (const row of rows) {
      for (const value of Object.values(row)) {
        if (typeof value !== 'string') continue;
        for (const line of value.split('\n')) {
          if (!TAP_LINE.test(line)) continue;
          const plan = /^1\.\.(\d+)/.exec(line);
          if (plan?.[1] !== undefined) report.planned = Number(plan[1]);
          else if (line.startsWith('not ok')) report.failed.push(line);
          else if (line.startsWith('ok')) report.passed += 1;
          else report.diagnostics.push(line);
        }
      }
    }
  }
  return report;
}

export function tapProblems(report: TapReport): string[] {
  const problems = [...report.failed];
  const ran = report.passed + report.failed.length;
  if (report.planned === null) problems.push('no plan: the file must call plan(n)');
  else if (report.planned !== ran) {
    problems.push(`planned ${String(report.planned)} test(s) but ran ${String(ran)}`);
  }
  return problems;
}
