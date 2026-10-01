import { describe, expect, it } from 'vitest';
import { isSlug, isUuid, safeNextPath } from './routing';

describe('safeNextPath', () => {
  it('keeps same-site paths with their query', () => {
    expect(safeNextPath('/w/jansen/clients?x=1')).toBe('/w/jansen/clients?x=1');
    expect(safeNextPath('/portal')).toBe('/portal');
  });

  it.each([
    ['https://evil.example/phish'],
    ['//evil.example'],
    ['/\\evil.example'],
    ['javascript:alert(1)'],
    ['relative/path'],
    ['/\u0000x'],
    [''],
    [undefined],
    [42],
  ])('rejects %j and falls back to /', (value) => {
    expect(safeNextPath(value)).toBe('/');
  });
});

describe('route id validation', () => {
  it('accepts canonical UUIDs only', () => {
    expect(isUuid('20000000-0000-4000-8000-00000000000a')).toBe(true);
    expect(isUuid('20000000-0000-4000-8000-00000000000a; drop')).toBe(false);
    expect(isUuid('not-a-uuid')).toBe(false);
  });

  it('accepts database slugs only', () => {
    expect(isSlug('jansen')).toBe(true);
    expect(isSlug('outra-agencia')).toBe(true);
    expect(isSlug('Jansen')).toBe(false);
    expect(isSlug('../etc')).toBe(false);
  });
});
