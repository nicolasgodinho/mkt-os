import { describe, expect, it } from 'vitest';
import { invitationUrl, isOpen, slugify, TOKEN } from './model';

describe('administration helpers', () => {
  it('builds the invitation link from the public origin', () => {
    const token = 'a'.repeat(64);
    expect(TOKEN.test(token)).toBe(true);
    expect(invitationUrl('https://os.jansen.com.br/', token)).toBe(
      `https://os.jansen.com.br/convite/${token}`,
    );
  });

  it('treats a pending invitation past its expiry as closed', () => {
    const now = new Date('2026-10-03T12:00:00Z');
    expect(isOpen({ status: 'pending', expires_at: '2026-10-04T00:00:00Z' }, now)).toBe(true);
    expect(isOpen({ status: 'pending', expires_at: '2026-10-03T11:00:00Z' }, now)).toBe(false);
    expect(isOpen({ status: 'accepted', expires_at: '2026-10-09T00:00:00Z' }, now)).toBe(false);
  });

  it('suggests client slugs the database accepts', () => {
    expect(slugify('Clínica Sorriso & Cia.')).toBe('clinica-sorriso-cia');
    expect(slugify('  --Ótica  São João--  ')).toBe('otica-sao-joao');
  });
});
