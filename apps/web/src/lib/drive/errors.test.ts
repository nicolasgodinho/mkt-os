import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { driveErrorMessage } from './errors';

const MIGRATIONS = path.resolve(import.meta.dirname, '../../../../../supabase/migrations');
const MIGRATION = path.join(MIGRATIONS, '20261002220000_drive_sync.sql');
const JOB_CENTER_MIGRATION = path.join(MIGRATIONS, '20261002120000_job_center.sql');
const GENERIC_INVALID = 'Esta ação não vale para o estado atual. Atualize a página.';

describe('driveErrorMessage', () => {
  it('maps the frozen error contract without revealing existence', () => {
    expect(driveErrorMessage({ code: 'P0002' })).toBe('Item não encontrado ou fora do seu acesso.');
    expect(driveErrorMessage({ code: '42501' })).toBe('Você não tem permissão para esta ação.');
    expect(driveErrorMessage({ code: '22023', message: 'constructor' })).toBe(GENERIC_INVALID);
  });

  it('has a specific message for every literal 22023 error raised by the migration', () => {
    const pattern = /raise exception '([^'%]+)'\s+using errcode = '22023'/g;
    const raised = (file: string) =>
      [...readFileSync(file, 'utf8').matchAll(pattern)].map((match) => match[1] ?? '');
    // The migration re-creates the job center's retry_job: its Increment 3 messages belong to
    // the job center, not to this map.
    const jobCenter = new Set(raised(JOB_CENTER_MIGRATION));
    const messages = raised(MIGRATION).filter((message) => !jobCenter.has(message));
    expect(messages).toContain('drive syncs are retried from the drive page');
    expect(messages.length).toBeGreaterThan(6);
    for (const message of messages) {
      expect(driveErrorMessage({ code: '22023', message }), message).not.toBe(GENERIC_INVALID);
    }
  });
});
