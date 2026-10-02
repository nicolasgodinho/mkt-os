import { describe, expect, it } from 'vitest';
import {
  ASSIGNABLE_TRUST_LEVELS,
  canPromoteFrom,
  formatDate,
  formatValidity,
  toBusinessTimestamp,
  validityState,
} from './model';

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

describe('formatValidity for inclusive offers', () => {
  it('does not claim an exclusive end', () => {
    expect(formatValidity('2026-01-01', '2026-12-31', 'inclusive')).toBe(
      '01/01/2026 até 31/12/2026',
    );
  });
});

describe('validityState (half-open windows)', () => {
  const at = new Date('2030-07-01T03:00:00Z');
  it('classifies current, expired and future windows', () => {
    expect(validityState(null, null, at)).toBe('current');
    expect(validityState('2030-07-01T03:00:00Z', null, at)).toBe('current');
    expect(validityState(null, '2030-07-01T03:00:00Z', at)).toBe('expired');
    expect(validityState('2030-08-01T00:00:00Z', null, at)).toBe('future');
  });
});

describe('toBusinessTimestamp', () => {
  it('pins calendar dates to midnight in the business timezone', () => {
    expect(toBusinessTimestamp('2026-10-01')).toBe('2026-10-01T00:00:00-03:00');
    expect(toBusinessTimestamp(null)).toBeNull();
  });
});
