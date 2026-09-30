import { describe, expect, it } from 'vitest';
import { jobIdempotencyKey, MAX_IDEMPOTENCY_KEY_LENGTH } from './idempotency';

const contract = { type: 'meeting.extract', schemaVersion: 1 };

describe('jobIdempotencyKey', () => {
  it('is deterministic for the same unit of work', () => {
    const a = jobIdempotencyKey(contract, ['meeting-123', 7]);
    const b = jobIdempotencyKey(contract, ['meeting-123', 7]);
    expect(a).toBe(b);
    expect(a).toBe('meeting.extract.v1:meeting-123:7');
  });

  it('distinguishes contract versions', () => {
    expect(jobIdempotencyKey({ ...contract, schemaVersion: 2 }, ['m'])).not.toBe(
      jobIdempotencyKey(contract, ['m']),
    );
  });

  it('cannot collide through delimiter characters inside parts', () => {
    expect(jobIdempotencyKey(contract, ['a:b'])).not.toBe(jobIdempotencyKey(contract, ['a', 'b']));
  });

  it('rejects keys that carry no unit-of-work identity', () => {
    expect(() => jobIdempotencyKey(contract, [])).toThrow(/at least one part/);
    expect(() => jobIdempotencyKey(contract, [''])).toThrow(/must not be empty/);
    expect(() => jobIdempotencyKey(contract, [Number.NaN])).toThrow(/finite/);
  });

  it('enforces the database length limit', () => {
    const long = 'x'.repeat(MAX_IDEMPOTENCY_KEY_LENGTH);
    expect(() => jobIdempotencyKey(contract, [long])).toThrow(RangeError);
  });
});
