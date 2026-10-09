import { describe, it, expect } from 'vitest';
import { safeNextPath } from './safe-redirect';

describe('safeNextPath', () => {
  const origin = 'http://127.0.0.1:3000';

  it('allows valid relative paths', () => {
    expect(safeNextPath('/ok?x=1', origin)).toBe('/ok?x=1');
    expect(safeNextPath('/convite/123', origin)).toBe('/convite/123');
    expect(safeNextPath('/conta/senha', origin)).toBe('/conta/senha');
  });

  it('rejects control characters (tab, CR, LF)', () => {
    expect(safeNextPath('/\tok', origin)).toBe('/');
    expect(safeNextPath('/ok\r\n', origin)).toBe('/');
    expect(safeNextPath('\u0000/ok', origin)).toBe('/');
  });

  it('rejects cross-origin attempts', () => {
    expect(safeNextPath('//evil.com', origin)).toBe('/');
    expect(safeNextPath('/\\evil.com', origin)).toBe('/');
    expect(safeNextPath('https://evil.com', origin)).toBe('/');
  });

  it('falls back to / on null or invalid next', () => {
    expect(safeNextPath(null, origin)).toBe('/');
    expect(safeNextPath('', origin)).toBe('/');
  });
});
