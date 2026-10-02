import { describe, expect, it } from 'vitest';
import { contextItemForm, knowledgeForm, reviewRuleForm, ruleForm } from './form-data';

const scope = { workspaceSlug: 'jansen', clientId: '20000000-0000-4000-8000-00000000000a' };
const source = '30000000-0000-4000-8000-000000000041';

describe('Client Brain form parsing', () => {
  it('turns empty optional fields into null', () => {
    const parsed = ruleForm.parse({
      ...scope,
      sourceId: source,
      type: 'PREFER',
      subject: '  ',
      statement: ' Frases curtas ',
      channel: '',
      priority: '70',
      effectiveFrom: '',
      effectiveUntil: '2030-01-01',
      supersedesRuleId: '',
    });
    expect(parsed).toMatchObject({
      subject: null,
      statement: 'Frases curtas',
      channel: null,
      priority: 70,
      effectiveFrom: null,
      effectiveUntil: '2030-01-01',
      supersedesRuleId: null,
    });
  });

  it('converts confidence from percent to 0–1', () => {
    const base = { ...scope, kind: 'insight', sourceId: source, statement: 'x' };
    expect(knowledgeForm.parse({ ...base, confidence: '40' }).confidence).toBe(0.4);
    expect(knowledgeForm.parse({ ...base, confidence: '' }).confidence).toBeNull();
    expect(knowledgeForm.safeParse({ ...base, confidence: '140' }).success).toBe(false);
  });

  it('rejects malformed scope, ids and enum values', () => {
    const audience = { ...scope, kind: 'audience', name: 'a' };
    expect(contextItemForm.safeParse({ ...audience, workspaceSlug: '../x' }).success).toBe(false);
    expect(contextItemForm.safeParse({ ...audience, kind: 'fact' }).success).toBe(false);
    expect(
      reviewRuleForm.safeParse({ ...scope, id: 'not-a-uuid', decision: 'activate' }).success,
    ).toBe(false);
    expect(reviewRuleForm.safeParse({ ...scope, id: source, decision: 'delete' }).success).toBe(
      false,
    );
  });

  it('requires a non-blank statement and name', () => {
    const fact = { ...scope, kind: 'fact', sourceId: source, statement: '   ' };
    expect(knowledgeForm.safeParse(fact).success).toBe(false);
    expect(contextItemForm.safeParse({ ...scope, kind: 'region', name: '' }).success).toBe(false);
  });
});
