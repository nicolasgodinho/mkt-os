import { describe, expect, it } from 'vitest';
import { capabilityListSchema, portalAreasFor } from './capabilities';

describe('portalAreasFor', () => {
  it('gives a viewer read-only areas', () => {
    expect(portalAreasFor(['client.view']).map((area) => area.key)).toEqual(['content']);
  });

  it('adds approvals only with approval.decide and requests only with request.submit', () => {
    expect(portalAreasFor(['client.view', 'approval.decide']).map((a) => a.key)).toEqual([
      'content',
      'approvals',
    ]);
    expect(portalAreasFor(['client.view', 'request.submit']).map((a) => a.key)).toEqual([
      'content',
      'requests',
    ]);
  });

  it('shows nothing without capabilities', () => {
    expect(portalAreasFor([])).toEqual([]);
  });
});

describe('capabilityListSchema', () => {
  it('accepts the database capability contract', () => {
    expect(capabilityListSchema.parse(['client.view', 'audit.view'])).toEqual([
      'client.view',
      'audit.view',
    ]);
  });

  it('rejects unknown capability values instead of passing them through', () => {
    expect(capabilityListSchema.safeParse(['client.view', 'root']).success).toBe(false);
  });
});
