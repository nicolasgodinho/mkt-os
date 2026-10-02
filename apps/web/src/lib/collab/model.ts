import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';
import { payloadSchema } from '../content/model';

/**
 * Collaboration and portal contract (tests/acceptance/increment-6/README.md) as seen by the web
 * app. Display helpers only: the database decides visibility and every decision.
 */

export const APPROVAL_STATUSES = [
  'requested',
  'approved',
  'changes_requested',
  'canceled',
  'expired',
] as const;
export type ApprovalStatus = (typeof APPROVAL_STATUSES)[number];

export const APPROVAL_STATUS: Record<ApprovalStatus, { label: string; tone: StatusTone }> = {
  requested: { label: 'Aguardando cliente', tone: 'warning' },
  approved: { label: 'Aprovado pelo cliente', tone: 'success' },
  changes_requested: { label: 'Alterações pedidas', tone: 'danger' },
  canceled: { label: 'Cancelado', tone: 'neutral' },
  expired: { label: 'Expirado', tone: 'neutral' },
};

export const approvalRequestSchema = z.object({
  id: z.uuid(),
  client_id: z.uuid(),
  content_id: z.uuid(),
  revision_id: z.uuid(),
  status: z.enum(APPROVAL_STATUSES),
  requested_at: z.string(),
  due_at: z.string().nullable(),
  decided_at: z.string().nullable(),
});
export type ApprovalRequest = z.infer<typeof approvalRequestSchema>;

export const portalApprovalSchema = z.object({
  request_id: z.uuid(),
  status: z.enum(APPROVAL_STATUSES),
  content_title: z.string(),
  channel: z.string(),
  format: z.string(),
  revision_number: z.number().int(),
  payload: payloadSchema,
  requested_at: z.string(),
  due_at: z.string().nullable(),
  decided_at: z.string().nullable(),
});
export type PortalApproval = z.infer<typeof portalApprovalSchema>;

export const decisionSchema = z.object({
  approval_request_id: z.uuid(),
  decision: z.enum(['approve', 'changes']),
  comment: z.string().nullable(),
  decided_at: z.string(),
});
export type ApprovalDecision = z.infer<typeof decisionSchema>;

export const commentSchema = z.object({
  id: z.uuid(),
  author_id: z.uuid(),
  author_name: z.string(),
  body: z.string(),
  created_at: z.string(),
  visibility: z.enum(['internal', 'client']),
});
export type Comment = z.infer<typeof commentSchema>;

/** "Needs you": open requests, the most urgent first (due date, then oldest). */
export function needsAttention(rows: readonly PortalApproval[]): PortalApproval[] {
  return rows
    .filter((row) => row.status === 'requested')
    .sort((a, b) => {
      if (a.due_at !== b.due_at) {
        if (a.due_at === null) return 1;
        if (b.due_at === null) return -1;
        return a.due_at.localeCompare(b.due_at);
      }
      return a.requested_at.localeCompare(b.requested_at);
    });
}
