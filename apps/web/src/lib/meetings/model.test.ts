import { describe, expect, it } from 'vitest';
import { brainSectionFor, formatConfidence, parseParticipants, toBusinessDateTime } from './model';

describe('meeting form helpers', () => {
  it('turns one participant per line into the participants array', () => {
    expect(parseParticipants('Ana (cliente)\r\n\n  Bruno  \n')).toEqual([
      { name: 'Ana (cliente)' },
      { name: 'Bruno' },
    ]);
    expect(parseParticipants(null)).toEqual([]);
    expect(parseParticipants(Array(60).fill('x').join('\n'))).toHaveLength(50);
  });

  it('pins datetime-local values to the business timezone', () => {
    expect(toBusinessDateTime('2026-10-01T14:30')).toBe('2026-10-01T14:30:00-03:00');
    expect(toBusinessDateTime('')).toBeNull();
    expect(toBusinessDateTime('amanhã')).toBeNull();
  });

  it('knows where accepted proposals live and formats confidence', () => {
    expect(brainSectionFor('rule')).toBe('rules');
    expect(brainSectionFor('fact')).toBe('knowledge');
    expect(brainSectionFor('task')).toBeNull();
    expect(formatConfidence(0.4)).toBe('40%');
    expect(formatConfidence(null)).toBeNull();
  });
});
