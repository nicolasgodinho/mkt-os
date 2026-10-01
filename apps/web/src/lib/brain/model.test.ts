import { describe, expect, it } from 'vitest';
import { ASSIGNABLE_TRUST_LEVELS, canPromoteFrom, formatDate, formatValidity } from './model';

describe('canPromoteFrom (docs/02 §5, TEST_SPEC decision 4)', () => {
  it('blocks facts, decisions and rules from untrusted sources but not insights', () => {
    expect(canPromoteFrom('fact', 'UNTRUSTED_EXTERNAL')).toBe(false);
    expect(canPromoteFrom('decision', 'UNTRUSTED_EXTERNAL')).toBe(false);
    expect(canPromoteFrom('rule', 'UNTRUSTED_EXTERNAL')).toBe(false);
    expect(canPromoteFrom('insight', 'UNTRUSTED_EXTERNAL')).toBe(true);
    expect(canPromoteFrom('fact', 'FIRST_PARTY')).toBe(true);
  });

  it('never offers SYSTEM trust to people', () => {
    expect(ASSIGNABLE_TRUST_LEVELS).not.toContain('SYSTEM');
  });
});

describe('formatDate / formatValidity', () => {
  it('formats the date part without timezone shifts', () => {
    expect(formatDate('2030-06-30T00:00:00+00:00')).toBe('30/06/2030');
    expect(formatDate('2026-01-01')).toBe('01/01/2026');
    expect(formatDate(null)).toBeNull();
  });

  it('describes half-open windows', () => {
    expect(formatValidity(null, null)).toBeNull();
    expect(formatValidity('2030-01-01', null)).toBe('a partir de 01/01/2030');
    expect(formatValidity(null, '2030-07-01')).toBe('até 01/07/2030 (exclusivo)');
    expect(formatValidity('2030-01-01', '2030-07-01')).toBe(
      '01/01/2030 até 01/07/2030 (exclusivo)',
    );
  });
});
