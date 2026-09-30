import { describe, expect, it } from 'vitest';
import { evaluateChanges, parseNameStatus } from './protected-paths';

const base = ['20260930120000_tenancy_kernel.sql', '20260930120100_job_queue.sql'];

describe('protected-authority policy', () => {
  it('parses git name-status output including renames', () => {
    expect(parseNameStatus('M\tdocs/00.md\nR100\ta.sql\tb.sql\n')).toEqual([
      { status: 'M', path: 'docs/00.md' },
      { status: 'R', path: 'b.sql', fromPath: 'a.sql' },
    ]);
  });

  it('allows ordinary feature changes', () => {
    const changes = [{ status: 'M', path: 'apps/web/src/app/page.tsx' }];
    expect(evaluateChanges(changes, [], base)).toEqual([]);
  });

  it('requires TEST_SPEC authority for protected acceptance tests', () => {
    const changes = [{ status: 'M', path: 'tests/acceptance/tenant.test.sql' }];
    expect(evaluateChanges(changes, [], base)).toHaveLength(1);
    expect(evaluateChanges(changes, ['authority:TEST_SPEC'], base)).toEqual([]);
    expect(evaluateChanges(changes, ['authority:ARCHITECTURE_CHANGE'], base)).toHaveLength(1);
  });

  it('requires ARCHITECTURE_CHANGE authority for the spec, agent rules and CI policy', () => {
    for (const path of ['docs/02_DOMAIN_MODEL.md', 'AGENTS.md', '.github/workflows/ci.yml']) {
      const changes = [{ status: 'M', path }];
      expect(evaluateChanges(changes, [], base)).toHaveLength(1);
      expect(evaluateChanges(changes, ['authority:ARCHITECTURE_CHANGE'], base)).toEqual([]);
    }
  });

  it('detects moving a protected file out of its protected directory', () => {
    const changes = [
      { status: 'R', path: 'tests/old/x.test.ts', fromPath: 'tests/acceptance/x.test.ts' },
    ];
    expect(evaluateChanges(changes, [], base)).toHaveLength(1);
  });

  it('keeps migrations append-only, whatever the labels', () => {
    const all = ['authority:TEST_SPEC', 'authority:ARCHITECTURE_CHANGE'];
    for (const status of ['M', 'D']) {
      const changes = [{ status, path: 'supabase/migrations/20260930120000_tenancy_kernel.sql' }];
      expect(evaluateChanges(changes, all, base)).toHaveLength(1);
    }
  });

  it('accepts a well-named migration that sorts last', () => {
    const changes = [{ status: 'A', path: 'supabase/migrations/20261001090000_client_brain.sql' }];
    expect(evaluateChanges(changes, [], base)).toEqual([]);
  });

  it('rejects misnamed or out-of-order migrations', () => {
    const misnamed = [{ status: 'A', path: 'supabase/migrations/add_things.sql' }];
    const early = [{ status: 'A', path: 'supabase/migrations/20260101000000_backdated.sql' }];
    expect(evaluateChanges(misnamed, [], base)).toHaveLength(1);
    expect(evaluateChanges(early, [], base)).toHaveLength(1);
  });
});
