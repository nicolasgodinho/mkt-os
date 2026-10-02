import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';

/**
 * Content core contract (tests/acceptance/increment-5/README.md) as seen by the web app. Display
 * and form helpers only: the database decides visibility, transitions and validation.
 */

export const INITIATIVE_KINDS = ['campaign', 'always_on', 'launch', 'activation'] as const;
export const INITIATIVE_STATUSES = [
  'draft',
  'planning',
  'production',
  'scheduled',
  'active',
  'completed',
  'paused',
  'canceled',
] as const;
export const CONTENT_STATUSES = [
  'idea',
  'brief',
  'ready',
  'producing',
  'internal_review',
  'client_review',
  'approved',
  'scheduled',
  'published',
  'analyzed',
  'canceled',
  'archived',
] as const;
export const RULE_CHECK_RESULTS = ['pass', 'violation', 'not_applicable'] as const;
export const DOR_FIELDS = ['objective', 'audience', 'message_or_angle', 'cta'] as const;

export type InitiativeKind = (typeof INITIATIVE_KINDS)[number];
export type InitiativeStatus = (typeof INITIATIVE_STATUSES)[number];
export type ContentStatus = (typeof CONTENT_STATUSES)[number];
export type RuleCheckResult = (typeof RULE_CHECK_RESULTS)[number];

export const INITIATIVE_KIND_LABELS: Record<InitiativeKind, string> = {
  campaign: 'Campanha',
  always_on: 'Always-on',
  launch: 'Lançamento',
  activation: 'Ativação',
};

export const INITIATIVE_STATUS: Record<InitiativeStatus, { label: string; tone: StatusTone }> = {
  draft: { label: 'Rascunho', tone: 'neutral' },
  planning: { label: 'Planejamento', tone: 'info' },
  production: { label: 'Produção', tone: 'info' },
  scheduled: { label: 'Agendada', tone: 'info' },
  active: { label: 'Ativa', tone: 'success' },
  completed: { label: 'Concluída', tone: 'success' },
  paused: { label: 'Pausada', tone: 'warning' },
  canceled: { label: 'Cancelada', tone: 'neutral' },
};

/**
 * docs/04 Initiative transitions (mirrors the database; the database decides). A paused
 * initiative resumes only to the state it was paused in: see `nextInitiativeStatuses`.
 */
export const INITIATIVE_NEXT: Record<InitiativeStatus, readonly InitiativeStatus[]> = {
  draft: ['planning', 'canceled'],
  planning: ['production', 'paused', 'canceled'],
  production: ['scheduled', 'paused', 'canceled'],
  scheduled: ['active', 'paused', 'canceled'],
  active: ['completed', 'paused', 'canceled'],
  paused: ['canceled'],
  completed: [],
  canceled: [],
};

export const OPPORTUNITY_STATUS: Record<
  'detected' | 'reviewed' | 'watching' | 'dismissed' | 'converted',
  { label: string; tone: StatusTone }
> = {
  detected: { label: 'Nova', tone: 'info' },
  reviewed: { label: 'Revisada', tone: 'info' },
  watching: { label: 'Acompanhando', tone: 'warning' },
  dismissed: { label: 'Descartada', tone: 'neutral' },
  converted: { label: 'Virou pauta', tone: 'success' },
};

export const PAUTA_STATUS: Record<
  'draft' | 'ready' | 'canceled',
  { label: string; tone: StatusTone }
> = {
  draft: { label: 'Rascunho', tone: 'neutral' },
  ready: { label: 'Pronta', tone: 'success' },
  canceled: { label: 'Cancelada', tone: 'neutral' },
};

export const CONTENT_STATUS: Record<ContentStatus, { label: string; tone: StatusTone }> = {
  idea: { label: 'Ideia', tone: 'neutral' },
  brief: { label: 'Briefing', tone: 'neutral' },
  ready: { label: 'Pronto para produzir', tone: 'info' },
  producing: { label: 'Em produção', tone: 'info' },
  internal_review: { label: 'Revisão interna', tone: 'warning' },
  client_review: { label: 'Revisão do cliente', tone: 'warning' },
  approved: { label: 'Aprovado', tone: 'success' },
  scheduled: { label: 'Agendado', tone: 'info' },
  published: { label: 'Publicado', tone: 'success' },
  analyzed: { label: 'Analisado', tone: 'success' },
  canceled: { label: 'Cancelado', tone: 'neutral' },
  archived: { label: 'Arquivado', tone: 'neutral' },
};

export const RULE_CHECK: Record<RuleCheckResult, { label: string; tone: StatusTone }> = {
  pass: { label: 'Atende', tone: 'success' },
  violation: { label: 'Viola', tone: 'danger' },
  not_applicable: { label: 'Não se aplica', tone: 'neutral' },
};

export const DOR_LABELS: Record<(typeof DOR_FIELDS)[number], string> = {
  objective: 'Objetivo',
  audience: 'Público',
  message_or_angle: 'Mensagem ou ângulo',
  cta: 'Chamada para ação (CTA)',
};

export const initiativeSchema = z.object({
  id: z.uuid(),
  kind: z.enum(INITIATIVE_KINDS),
  name: z.string(),
  status: z.enum(INITIATIVE_STATUSES),
  paused_from: z.enum(INITIATIVE_STATUSES).nullable(),
  start_at: z.string().nullable(),
  end_at: z.string().nullable(),
});
export type Initiative = z.infer<typeof initiativeSchema>;

export const opportunitySchema = z.object({
  id: z.uuid(),
  type: z.string(),
  title: z.string(),
  reason: z.string(),
  status: z.enum(['detected', 'reviewed', 'watching', 'dismissed', 'converted']),
  confidence: z.number().nullable(),
  expires_at: z.string().nullable(),
  evidence_refs: z.array(z.uuid()),
  created_at: z.string(),
});
export type Opportunity = z.infer<typeof opportunitySchema>;

export const pautaSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  status: z.enum(['draft', 'ready', 'canceled']),
  initiative_id: z.uuid().nullable(),
  opportunity_id: z.uuid().nullable(),
  objective: z.string().nullable(),
  audience_ids: z.array(z.uuid()),
  pillar: z.string().nullable(),
  angle: z.string().nullable(),
  message: z.string().nullable(),
  cta: z.string().nullable(),
  offer_id: z.uuid().nullable(),
  source_ids: z.array(z.uuid()),
  mandatories: z.string().nullable(),
  constraints: z.string().nullable(),
  created_at: z.string(),
});
export type Pauta = z.infer<typeof pautaSchema>;

export const payloadSchema = z
  .object({
    headline: z.string().optional(),
    body: z.string().optional(),
    cta: z.string().optional(),
    hashtags: z.array(z.string()).optional(),
    alt_text: z.string().optional(),
  })
  .loose();
export type ContentPayload = z.infer<typeof payloadSchema>;

export const contentSchema = z.object({
  id: z.uuid(),
  pauta_id: z.uuid(),
  channel: z.string(),
  format: z.string(),
  title: z.string(),
  status: z.enum(CONTENT_STATUSES),
  working_payload: payloadSchema,
  current_revision_id: z.uuid().nullable(),
  approved_revision_id: z.uuid().nullable(),
  client_approved_revision_id: z.uuid().nullable(),
  production_due_at: z.string().nullable(),
  updated_at: z.string(),
});
export type Content = z.infer<typeof contentSchema>;

export const revisionSchema = z.object({
  id: z.uuid(),
  revision_number: z.number().int(),
  payload: payloadSchema,
  immutable_hash: z.string(),
  created_at: z.string(),
});
export type Revision = z.infer<typeof revisionSchema>;

export const validationSchema = z.object({
  rule_id: z.uuid(),
  type: z.enum(['MUST', 'MUST_NOT', 'PREFER', 'AVOID']),
  subject: z.string().nullable(),
  statement: z.string(),
  result: z.enum(RULE_CHECK_RESULTS).nullable(),
  blocking: z.boolean(),
});
export type ValidationRow = z.infer<typeof validationSchema>;

/** Hashtags typed one per line or separated by spaces → `#tag` list (max 30). */
export function parseHashtags(text: string | null | undefined): string[] {
  return (text ?? '')
    .split(/[\s,]+/)
    .map((tag) => tag.trim())
    .filter((tag) => tag !== '')
    .map((tag) => (tag.startsWith('#') ? tag : `#${tag}`).slice(0, 100))
    .slice(0, 30);
}

/** Builds the payload from the studio form; empty optional fields are omitted. */
export function buildPayload(fields: {
  headline?: string | null;
  body?: string | null;
  cta?: string | null;
  hashtags?: string | null;
  alt_text?: string | null;
}): ContentPayload {
  const payload: ContentPayload = {};
  for (const key of ['headline', 'body', 'cta', 'alt_text'] as const) {
    const value = fields[key]?.trim();
    if (value) payload[key] = value;
  }
  const hashtags = parseHashtags(fields.hashtags);
  if (hashtags.length > 0) payload.hashtags = hashtags;
  return payload;
}

export function nextInitiativeStatuses(initiative: {
  status: InitiativeStatus;
  paused_from: InitiativeStatus | null;
}): InitiativeStatus[] {
  if (initiative.status === 'paused' && initiative.paused_from !== null) {
    return [initiative.paused_from, 'canceled'];
  }
  return [...INITIATIVE_NEXT[initiative.status]];
}
