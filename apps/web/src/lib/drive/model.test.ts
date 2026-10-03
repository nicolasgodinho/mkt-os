import { describe, expect, it } from 'vitest';
import { extractFolderId, failureMessage, formatSize, syncState, type SyncJob } from './model';

const NOW = new Date('2026-10-02T12:00:00Z');

function job(status: SyncJob['status'], runAfter: string, code?: string): SyncJob {
  return {
    id: '20000000-0000-4000-8000-0000000000ff',
    status,
    attempts: 1,
    run_after: runAfter,
    last_error: code === undefined ? null : { code },
    finished_at: null,
    created_at: '2026-10-02T11:00:00Z',
  };
}

describe('syncState', () => {
  it('derives the connection state from its latest sync job', () => {
    const active = { status: 'active' as const };
    expect(syncState({ status: 'paused' }, job('running', NOW.toISOString()), NOW)).toEqual({
      kind: 'paused',
    });
    expect(syncState(active, null, NOW)).toEqual({ kind: 'idle' });
    expect(syncState(active, job('running', '2026-10-02T11:59:00Z'), NOW)).toEqual({
      kind: 'running',
    });
    expect(syncState(active, job('queued', '2026-10-02T11:59:00Z'), NOW)).toEqual({
      kind: 'queued',
    });
    expect(syncState(active, job('queued', '2026-10-02T13:00:00Z'), NOW)).toEqual({
      kind: 'scheduled',
      at: '2026-10-02T13:00:00Z',
    });
    expect(
      syncState(active, job('retry_wait', '2026-10-02T12:05:00Z', 'drive_unavailable'), NOW),
    ).toEqual({ kind: 'retrying', at: '2026-10-02T12:05:00Z', code: 'drive_unavailable' });
    expect(syncState(active, job('failed', NOW.toISOString(), 'drive_auth_failed'), NOW)).toEqual({
      kind: 'failed',
      code: 'drive_auth_failed',
    });
    expect(syncState(active, job('completed', NOW.toISOString()), NOW)).toEqual({ kind: 'idle' });
  });
});

describe('helpers', () => {
  it('explains worker failure codes', () => {
    expect(failureMessage('drive_credentials_missing')).toMatch(/JMOS_DRIVE_CREDENTIALS_DIR/);
    expect(failureMessage('constructor')).toBe('A sincronização falhou.');
    expect(failureMessage(null)).toBe('A sincronização falhou.');
  });

  it('accepts a folder link or a bare id', () => {
    expect(
      extractFolderId('https://drive.google.com/drive/folders/1AbCdEfGhIjK_lm-N?usp=sharing'),
    ).toBe('1AbCdEfGhIjK_lm-N');
    expect(extractFolderId('  1AbCdEfGhIjK  ')).toBe('1AbCdEfGhIjK');
  });

  it('formats sizes', () => {
    expect(formatSize(null)).toBeNull();
    expect(formatSize(512)).toBe('512 B');
    expect(formatSize(2048)).toBe('2 KB');
    expect(formatSize(5 * 1024 * 1024)).toBe('5 MB');
  });
});
