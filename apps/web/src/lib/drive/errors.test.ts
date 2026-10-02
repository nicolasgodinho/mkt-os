import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { driveErrorMessage } from './errors';

const MIGRATION = path.resolve(
  import.meta.dirname,
  '../../../../../supabase/migrations/20261002220000_drive_sync.sql',
);
const GENERIC_INVALID = 'Esta ação não vale para o estado atual. Atualize a página.';

describe('driveErrorMessage', () => {
  it('maps the frozen error contract without revealing existence', () => {
    expect(driveErrorMessage({ code: 'P0002' })).toBe('Item não encontrado ou fora do seu acesso.');
    expect(driveErrorMessage({ code: '42501' })).toBe('Você não tem permissão para esta ação.');
    expect(driveErrorMessage({ code: '22023', message: 'constructor' })).toBe(GENERIC_INVALID);
  });

  it('has a specific message for every literal 22023 error raised by the migration', () => {
    const sql = readFileSync(MIGRATION, 'utf8');
    const pattern = /raise exception '([^'%]+)'\s+using errcode = '22023'/g;
    const messages = [...sql.matchAll(pattern)].map((match) => match[1] ?? '');
    expect(messages.length).toBeGreaterThan(6);
    for (const message of messages) {
      expect(driveErrorMessage({ code: '22023', message }), message).not.toBe(GENERIC_INVALID);
    }
  });
});
