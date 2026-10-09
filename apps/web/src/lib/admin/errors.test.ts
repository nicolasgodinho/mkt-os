import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { adminErrorMessage } from './errors';

const MIGRATIONS = path.resolve(import.meta.dirname, '../../../../../supabase/migrations');
const SOURCES = ['20260930140000_identity_authorization.sql', '20261003120000_invitations.sql'];
const GENERIC_INVALID = 'Esta ação não vale para o estado atual. Atualize a página.';

describe('adminErrorMessage', () => {
  it('maps the frozen error contract without revealing existence', () => {
    expect(adminErrorMessage({ code: 'P0002' })).toBe('Item não encontrado ou fora do seu acesso.');
    expect(adminErrorMessage({ code: '42501' })).toBe('Você não tem permissão para esta ação.');
    expect(adminErrorMessage({ code: '23505' })).toMatch(/identificador/);
    expect(adminErrorMessage({ code: '22023', message: 'constructor' })).toBe(GENERIC_INVALID);
  });

  it('has a specific message for every literal 22023 error of the identity and invitation API', () => {
    const pattern = /raise exception '([^'%]+)'\s+using errcode = '22023'/g;
    const messages = SOURCES.flatMap((file) =>
      [...readFileSync(path.join(MIGRATIONS, file), 'utf8').matchAll(pattern)].map(
        (match) => match[1] ?? '',
      ),
    );
    expect(messages).toContain('this invitation is not valid');
    for (const message of messages) {
      expect(adminErrorMessage({ code: '22023', message }), message).not.toBe(GENERIC_INVALID);
    }
  });
});
