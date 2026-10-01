import { describe, expect, it } from 'vitest';
import { filterRules, normalizeChannel, parseKnowledgeFilters, parseRuleFilters } from './filters';
import type { Rule } from './model';

describe('parseKnowledgeFilters', () => {
  it('keeps known values and ignores the rest', () => {
    expect(
      parseKnowledgeFilters({ kind: 'fact', status: 'proposed', trust: 'FIRST_PARTY' }),
    ).toEqual({ kind: 'fact', status: 'proposed', trust: 'FIRST_PARTY' });
    expect(parseKnowledgeFilters({ kind: 'rule', status: ['active', 'x'], trust: '' })).toEqual({
      kind: null,
      status: 'active',
      trust: null,
    });
  });
});

describe('parseRuleFilters / normalizeChannel', () => {
  it('normalizes channels like the database', () => {
    expect(normalizeChannel('  Instagram ')).toBe('instagram');
    expect(normalizeChannel('insta gram')).toBeNull();
    expect(normalizeChannel('')).toBeNull();
    expect(normalizeChannel(undefined)).toBeNull();
    expect(parseRuleFilters({ type: 'MUST_NOT', scope: 'channel', channel: 'LinkedIn' })).toEqual({
      type: 'MUST_NOT',
      status: null,
      scope: 'channel',
      channel: 'linkedin',
    });
  });
});

describe('filterRules', () => {
  const rule = (overrides: Partial<Rule>): Rule => ({
    id: '00000000-0000-4000-8000-000000000001',
    source_id: '00000000-0000-4000-8000-000000000002',
    type: 'MUST',
    subject: 'cta',
    statement: 'x',
    scope_type: 'client',
    channel: null,
    priority: 50,
    status: 'active',
    effective_from: null,
    effective_until: null,
    supersedes_rule_id: null,
    created_at: '2026-10-01T00:00:00Z',
    ...overrides,
  });

  it('narrows by type, status and scope', () => {
    const rules = [
      rule({ id: '00000000-0000-4000-8000-0000000000a1' }),
      rule({ id: '00000000-0000-4000-8000-0000000000a2', status: 'conflict' }),
      rule({ id: '00000000-0000-4000-8000-0000000000a3', scope_type: 'channel', channel: 'x' }),
    ];
    const none = { type: null, status: null, scope: null, channel: null };
    expect(filterRules(rules, none)).toHaveLength(3);
    expect(filterRules(rules, { ...none, status: 'conflict' }).map((r) => r.id)).toEqual([
      '00000000-0000-4000-8000-0000000000a2',
    ]);
    expect(filterRules(rules, { ...none, scope: 'channel' })).toHaveLength(1);
    expect(filterRules(rules, { ...none, type: 'AVOID' })).toHaveLength(0);
  });
});
