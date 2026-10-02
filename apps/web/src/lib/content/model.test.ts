import { describe, expect, it } from 'vitest';
import { INITIATIVE_NEXT, buildPayload, parseHashtags } from './model';

describe('content studio helpers', () => {
  it('normalizes hashtags', () => {
    expect(parseHashtags('sorriso #saude, familia')).toEqual(['#sorriso', '#saude', '#familia']);
    expect(parseHashtags('')).toEqual([]);
    expect(parseHashtags(Array(40).fill('x').join(' '))).toHaveLength(30);
  });

  it('builds the payload without empty fields', () => {
    expect(buildPayload({ headline: '  ', body: ' Texto ', cta: '', hashtags: 'a b' })).toEqual({
      body: 'Texto',
      hashtags: ['#a', '#b'],
    });
  });

  it('mirrors the frozen initiative transitions', () => {
    expect(INITIATIVE_NEXT.production).not.toContain('completed');
    expect(INITIATIVE_NEXT.canceled).toEqual([]);
    expect(INITIATIVE_NEXT.paused).toContain('active');
  });
});
