import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { calendarErrorMessage } from './errors';

const MIGRATION = path.resolve(
  import.meta.dirname,
  '../../../../../supabase/migrations/20261002200000_calendar_publication.sql',
);
const GENERIC_INVALID = 'Esta ação não vale para o estado atual. Atualize a página.';

describe('calendarErrorMessage', () => {
  it('maps the frozen error contract without revealing existence', () => {
    expect(calendarErrorMessage({ code: 'P0002', message: 'not found' })).toBe(
      'Item não encontrado ou fora do seu acesso.',
    );
    expect(calendarErrorMessage({ code: '42501', message: 'permission denied' })).toBe(
      'Você não tem permissão para esta ação.',
    );
    expect(calendarErrorMessage({ code: 'XX000' })).toBe(
      'Não foi possível concluir a ação. Tente novamente.',
    );
    expect(calendarErrorMessage({ code: '22023', message: 'constructor' })).toBe(GENERIC_INVALID);
  });

  it('has a specific message for every literal 22023 error raised by the migration', () => {
    const sql = readFileSync(MIGRATION, 'utf8');
    const pattern = /raise exception '([^'%]+)'\s+using errcode = '22023'/g;
    const messages = [...sql.matchAll(pattern)].map((match) => match[1] ?? '');
    expect(messages.length).toBeGreaterThan(5);
    for (const message of messages) {
      expect(calendarErrorMessage({ code: '22023', message }), message).not.toBe(GENERIC_INVALID);
    }
  });
});
