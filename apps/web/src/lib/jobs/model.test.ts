import { describe, expect, it } from 'vitest';
import { jobErrorMessage } from './errors';
import {
  CANCELABLE,
  RETRYABLE,
  WORKER_OFFLINE_AFTER_MS,
  contractKey,
  formatDateTime,
  isStalled,
  isWorkerOnline,
  type WorkerHeartbeat,
} from './model';

const now = new Date('2026-10-02T15:00:00Z');

function worker(overrides: Partial<WorkerHeartbeat>): WorkerHeartbeat {
  return {
    worker_id: 'gpu-box',
    status: 'idle',
    version: '0.1.0',
    job_types: ['system.healthcheck.v1'],
    active_model_profile: null,
    last_seen_at: '2026-10-02T14:59:50Z',
    ...overrides,
  };
}

describe('worker liveness (docs/15)', () => {
  it('is online with a recent heartbeat and offline when stale or stopped', () => {
    expect(isWorkerOnline(worker({}), now)).toBe(true);
    const stale = new Date(now.getTime() - WORKER_OFFLINE_AFTER_MS).toISOString();
    expect(isWorkerOnline(worker({ last_seen_at: stale }), now)).toBe(false);
    expect(isWorkerOnline(worker({ status: 'stopped' }), now)).toBe(false);
  });
});

describe('stalled jobs (ADR 0001)', () => {
  it('flags running jobs whose lease expired', () => {
    expect(isStalled({ status: 'running', lease_until: '2026-10-02T14:00:00Z' }, now)).toBe(true);
    expect(isStalled({ status: 'running', lease_until: '2026-10-02T16:00:00Z' }, now)).toBe(false);
    expect(isStalled({ status: 'queued', lease_until: null }, now)).toBe(false);
  });
});

describe('job center rules mirrored for display', () => {
  it('matches the frozen cancel/retry states', () => {
    expect([...CANCELABLE]).toEqual(['queued', 'retry_wait']);
    expect([...RETRYABLE]).toEqual(['failed', 'dead_letter', 'canceled']);
  });

  it('formats keys, dates and errors', () => {
    expect(contractKey({ type: 'ai.model_check', schema_version: 1 })).toBe('ai.model_check.v1');
    expect(formatDateTime('2026-10-02T15:00:00Z')).toBe('02/10/2026, 12:00');
    expect(formatDateTime('nope')).toBeNull();
    expect(jobErrorMessage({ code: '42501' })).toMatch(/permissão/);
    expect(jobErrorMessage({ code: 'XX000' })).toMatch(/Tente novamente/);
  });
});
