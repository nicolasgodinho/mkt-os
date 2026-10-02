import { describe, expect, it } from 'vitest';
import {
  businessDay,
  groupByDay,
  monthGrid,
  monthRange,
  parseMonth,
  shiftMonth,
  toBusinessDateTime,
  toDateTimeLocal,
  type CalendarEvent,
} from './model';

function event(startsAt: string, id: string): CalendarEvent {
  return {
    event_type: 'publication',
    client_id: '20000000-0000-4000-8000-00000000000a',
    entity_id: id,
    content_id: null,
    title: id,
    starts_at: startsAt,
    status: 'scheduled',
    date_field: 'scheduled_at',
  };
}

describe('business dates', () => {
  it('uses the business timezone for days and datetime inputs', () => {
    // 01:30 UTC on the 6th is still the 5th in São Paulo (-03:00).
    expect(businessDay('2026-10-06T01:30:00Z')).toBe('2026-10-05');
    expect(toBusinessDateTime('2026-10-05T22:30')).toBe('2026-10-05T22:30:00-03:00');
    expect(toDateTimeLocal('2026-10-06T01:30:00Z')).toBe('2026-10-05T22:30');
    expect(toDateTimeLocal(null)).toBe('');
  });

  it('refuses malformed datetime input', () => {
    expect(toBusinessDateTime('2026-10-05')).toBeNull();
    expect(toBusinessDateTime('amanhã')).toBeNull();
  });
});

describe('months', () => {
  it('parses, shifts and bounds months', () => {
    const now = new Date('2026-10-02T12:00:00Z');
    expect(parseMonth('2026-12', now)).toBe('2026-12');
    expect(parseMonth('2026-13', now)).toBe('2026-10');
    expect(parseMonth(undefined, now)).toBe('2026-10');
    expect(shiftMonth('2026-12', 1)).toBe('2027-01');
    expect(shiftMonth('2026-01', -1)).toBe('2025-12');
    expect(monthRange('2026-12')).toEqual({
      from: '2026-12-01T00:00:00-03:00',
      to: '2027-01-01T00:00:00-03:00',
    });
  });

  it('builds Monday-first weeks covering the whole month', () => {
    const weeks = monthGrid('2026-10');
    // October 2026 starts on a Thursday and ends on a Saturday.
    expect(weeks[0]).toEqual([
      '2026-09-28',
      '2026-09-29',
      '2026-09-30',
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
    ]);
    expect(weeks.at(-1)?.at(-1)).toBe('2026-11-01');
    expect(weeks.every((week) => week.length === 7)).toBe(true);
  });
});

describe('groupByDay', () => {
  it('groups events by business day in order', () => {
    const days = groupByDay([
      event('2026-10-05T12:00:00Z', 'a'),
      event('2026-10-06T01:00:00Z', 'b'),
      event('2026-10-06T12:00:00Z', 'c'),
    ]);
    expect([...days.keys()]).toEqual(['2026-10-05', '2026-10-06']);
    expect(days.get('2026-10-05')?.map((e) => e.entity_id)).toEqual(['a', 'b']);
  });
});
