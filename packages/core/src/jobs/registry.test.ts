import { describe, expect, it } from 'vitest';
import { jobContractKey } from './contract';
import { jobContracts } from './registry';
import { systemHealthcheckV1 } from './system-healthcheck';

describe('job contract registry', () => {
  it('has unique contract keys', () => {
    const keys = jobContracts.map((c) => jobContractKey(c));
    expect(new Set(keys).size).toBe(keys.length);
  });
});

describe('system.healthcheck v1', () => {
  it('accepts only an empty input object', () => {
    expect(systemHealthcheckV1.input.safeParse({}).success).toBe(true);
    expect(systemHealthcheckV1.input.safeParse({ sql: 'drop table jobs' }).success).toBe(false);
  });

  it('requires a complete, strict output', () => {
    const valid = {
      worker_id: 'gpu-box-1',
      worker_version: '0.1.0',
      checked_at: '2026-09-30T12:00:00.123456+00:00',
    };
    expect(systemHealthcheckV1.output.safeParse(valid).success).toBe(true);
    expect(systemHealthcheckV1.output.safeParse({ ...valid, extra: true }).success).toBe(false);
    expect(
      systemHealthcheckV1.output.safeParse({ ...valid, checked_at: 'yesterday' }).success,
    ).toBe(false);
  });
});
