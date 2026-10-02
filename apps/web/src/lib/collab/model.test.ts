import { describe, expect, it } from 'vitest';
import { needsAttention, type PortalApproval } from './model';

function row(
  id: string,
  status: PortalApproval['status'],
  requestedAt: string,
  dueAt: string | null,
): PortalApproval {
  return {
    request_id: id,
    status,
    content_title: id,
    channel: 'instagram',
    format: 'post',
    revision_number: 1,
    payload: { body: 'texto' },
    requested_at: requestedAt,
    due_at: dueAt,
    decided_at: null,
  };
}

describe('needsAttention', () => {
  it('keeps only open requests, earliest due date first, undated last by age', () => {
    const rows = [
      row('undated-new', 'requested', '2026-10-02T10:00:00Z', null),
      row('approved', 'approved', '2026-09-01T10:00:00Z', '2026-09-02T10:00:00Z'),
      row('due-late', 'requested', '2026-09-30T10:00:00Z', '2026-10-10T10:00:00Z'),
      row('undated-old', 'requested', '2026-09-20T10:00:00Z', null),
      row('due-soon', 'requested', '2026-10-01T10:00:00Z', '2026-10-03T10:00:00Z'),
      row('canceled', 'canceled', '2026-09-25T10:00:00Z', null),
    ];
    expect(needsAttention(rows).map((r) => r.request_id)).toEqual([
      'due-soon',
      'due-late',
      'undated-old',
      'undated-new',
    ]);
  });

  it('does not mutate its input', () => {
    const rows = [
      row('b', 'requested', '2026-10-02T10:00:00Z', null),
      row('a', 'requested', '2026-10-01T10:00:00Z', null),
    ];
    needsAttention(rows);
    expect(rows.map((r) => r.request_id)).toEqual(['b', 'a']);
  });
});
