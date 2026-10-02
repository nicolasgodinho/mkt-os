import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { brainErrorMessage, isExpectedBrainError } from './errors';

const MIGRATION = path.resolve(
  import.meta.dirname,
  '../../../../../supabase/migrations/20261001120000_client_brain.sql',
);
const GENERIC_INVALID = 'Dados inválidos. Revise os campos e tente novamente.';

describe('brainErrorMessage', () => {
  it('maps the frozen error contract without revealing existence', () => {
    expect(brainErrorMessage({ code: 'P0002', message: 'not found' })).toBe(
      'Item não encontrado ou fora do seu acesso.',
    );
    expect(brainErrorMessage({ code: '42501', message: 'permission denied' })).toBe(
      'Você não tem permissão para esta ação.',
    );
    expect(brainErrorMessage({ code: 'XX000', message: 'boom' })).toBe(
      'Não foi possível concluir a ação. Tente novamente.',
    );
  });

  it('explains the trust rule', () => {
    expect(
      brainErrorMessage({ code: '22023', message: 'untrusted sources cannot become rules' }),
    ).toMatch(/não confiáveis/);
  });

  it('maps "<field> is required" and unknown 22023 messages', () => {
    expect(brainErrorMessage({ code: '22023', message: 'statement is required' })).toBe(
      'Preencha os campos obrigatórios.',
    );
    expect(brainErrorMessage({ code: '22023', message: 'constructor' })).toBe(GENERIC_INVALID);
    expect(brainErrorMessage({ code: '22023' })).toBe(GENERIC_INVALID);
  });

  it('has a specific message for every literal 22023 error raised by the migration', () => {
    const sql = readFileSync(MIGRATION, 'utf8');
    const pattern = /raise exception '([^'%]+)' using errcode = '22023'/g;
    const messages = [...sql.matchAll(pattern)].map((match) => match[1] ?? '');
    expect(messages.length).toBeGreaterThan(10);
    for (const message of messages) {
      expect(brainErrorMessage({ code: '22023', message }), message).not.toBe(GENERIC_INVALID);
    }
  });

  it('classifies expected errors', () => {
    expect(isExpectedBrainError({ code: '22023' })).toBe(true);
    expect(isExpectedBrainError({ code: 'P0002' })).toBe(true);
    expect(isExpectedBrainError({ code: '42501' })).toBe(true);
    expect(isExpectedBrainError({ code: '23505' })).toBe(false);
  });
});
