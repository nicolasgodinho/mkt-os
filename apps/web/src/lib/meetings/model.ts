import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';
import { BUSINESS_UTC_OFFSET } from '../brain/model';

/**
 * Meeting intelligence contract (tests/acceptance/increment-4/README.md) as seen by the web app.
 * Display helpers only: the database decides visibility and every action.
 */

export const MEETING_STATUSES = [
  'new',
  'transcribing',
  'transcribed',
  'extracting',
  'in_review',
] as const;
export type MeetingStatus = (typeof MEETING_STATUSES)[number];

export const MEETING_STATUS: Record<MeetingStatus, { label: string; tone: StatusTone }> = {
  new: { label: 'Sem transcrição', tone: 'neutral' },
  transcribing: { label: 'Transcrevendo', tone: 'info' },
  transcribed: { label: 'Transcrição pronta', tone: 'info' },
  extracting: { label: 'Extraindo conhecimento', tone: 'info' },
  in_review: { label: 'Em revisão', tone: 'warning' },
};

export const PROPOSAL_KINDS = ['fact', 'decision', 'rule', 'insight', 'task'] as const;
export type ProposalKind = (typeof PROPOSAL_KINDS)[number];

export const PROPOSAL_KIND_LABELS: Record<ProposalKind, string> = {
  fact: 'Fato',
  decision: 'Decisão',
  rule: 'Regra',
  insight: 'Insight',
  task: 'Tarefa ou pergunta',
};

export const PROPOSAL_STATUS: Record<
  'proposed' | 'accepted' | 'rejected',
  { label: string; tone: StatusTone }
> = {
  proposed: { label: 'Para revisar', tone: 'warning' },
  accepted: { label: 'Aceito no Client Brain', tone: 'success' },
  rejected: { label: 'Rejeitado', tone: 'neutral' },
};

const participantSchema = z.object({ name: z.string() }).loose();

export const meetingSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  starts_at: z.string(),
  ends_at: z.string().nullable(),
  participants: z.array(participantSchema),
  recording_ref: z.string().nullable(),
  processing_status: z.enum(MEETING_STATUSES),
  transcript_source_id: z.uuid(),
});
export type Meeting = z.infer<typeof meetingSchema>;

export const transcriptSchema = z.object({
  revision: z.number().int(),
  text: z.string(),
  origin: z.enum(['manual', 'transcription']),
  created_at: z.string(),
});
export type MeetingTranscript = z.infer<typeof transcriptSchema>;

export const proposalSchema = z.object({
  id: z.uuid(),
  kind: z.enum(PROPOSAL_KINDS),
  statement: z.string(),
  rule_type: z.enum(['MUST', 'MUST_NOT', 'PREFER', 'AVOID']).nullable(),
  subject: z.string().nullable(),
  confidence: z.number().nullable(),
  evidence_quote: z.string().nullable(),
  time_ref: z.string().nullable(),
  status: z.enum(['proposed', 'accepted', 'rejected']),
  accepted_item_id: z.uuid().nullable(),
  transcript_revision: z.number().int(),
});
export type MeetingProposal = z.infer<typeof proposalSchema>;

export const meetingJobSchema = z.object({
  id: z.uuid(),
  type: z.string(),
  status: z.enum([
    'queued',
    'running',
    'retry_wait',
    'completed',
    'failed',
    'dead_letter',
    'canceled',
  ]),
  last_error: z
    .object({ code: z.string().optional(), message: z.string().optional() })
    .loose()
    .nullable(),
  created_at: z.string(),
});
export type MeetingJob = z.infer<typeof meetingJobSchema>;

/** One participant per line → `[{name}]` (blank lines dropped). */
export function parseParticipants(text: string | null): { name: string }[] {
  return (text ?? '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line !== '')
    .slice(0, 50)
    .map((name) => ({ name: name.slice(0, 200) }));
}

/** `2026-10-01T14:30` (datetime-local) → timestamp in the business timezone. */
export function toBusinessDateTime(value: string | null): string | null {
  if (value === null || value === '') return null;
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value) ? `${value}:00${BUSINESS_UTC_OFFSET}` : null;
}

/** Where an accepted proposal lives in the Client Brain. */
export function brainSectionFor(kind: ProposalKind): 'knowledge' | 'rules' | null {
  if (kind === 'rule') return 'rules';
  if (kind === 'task') return null;
  return 'knowledge';
}

export function formatConfidence(confidence: number | null): string | null {
  return confidence === null ? null : `${Math.round(confidence * 100).toString()}%`;
}
