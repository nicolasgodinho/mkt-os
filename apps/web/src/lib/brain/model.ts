import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';

/**
 * Client Brain contract (tests/acceptance/increment-2/README.md) as seen by the web app: enum
 * values mirror the database types, labels are pt-BR. Authorization is always decided by the
 * database; nothing here grants or hides access on its own.
 */

export const RULE_TYPES = ['MUST', 'MUST_NOT', 'PREFER', 'AVOID'] as const;
export const RULE_STATUSES = [
  'proposed',
  'active',
  'conflict',
  'superseded',
  'rejected',
  'expired',
] as const;
export const RULE_SCOPES = ['client', 'channel'] as const;
export const KNOWLEDGE_KINDS = ['fact', 'decision', 'insight'] as const;
export const KNOWLEDGE_STATUSES = ['proposed', 'active', 'rejected'] as const;
export const SOURCE_TYPES = [
  'document',
  'meeting',
  'website',
  'analytics',
  'review',
  'social_post',
  'user_input',
] as const;
export const SOURCE_TRUST_LEVELS = [
  'SYSTEM',
  'APPROVED_CLIENT',
  'FIRST_PARTY',
  'TRUSTED_EXTERNAL',
  'UNTRUSTED_EXTERNAL',
] as const;
/** Trust levels a person may assign through the API (SYSTEM is reserved). */
export const ASSIGNABLE_TRUST_LEVELS = SOURCE_TRUST_LEVELS.filter((level) => level !== 'SYSTEM');
export const CONTEXT_KINDS = ['audience', 'offer', 'region'] as const;

export type RuleType = (typeof RULE_TYPES)[number];
export type RuleStatus = (typeof RULE_STATUSES)[number];
export type RuleScope = (typeof RULE_SCOPES)[number];
export type KnowledgeKind = (typeof KNOWLEDGE_KINDS)[number];
export type KnowledgeStatus = (typeof KNOWLEDGE_STATUSES)[number];
export type SourceType = (typeof SOURCE_TYPES)[number];
export type SourceTrust = (typeof SOURCE_TRUST_LEVELS)[number];
export type ContextKind = (typeof CONTEXT_KINDS)[number];

export const HARD_RULE_TYPES: readonly RuleType[] = ['MUST', 'MUST_NOT'];

export const RULE_TYPE_LABELS: Record<RuleType, string> = {
  MUST: 'Obrigatório (MUST)',
  MUST_NOT: 'Proibido (MUST NOT)',
  PREFER: 'Preferir (PREFER)',
  AVOID: 'Evitar (AVOID)',
};

export const RULE_STATUS: Record<RuleStatus, { label: string; tone: StatusTone }> = {
  proposed: { label: 'Proposta', tone: 'warning' },
  active: { label: 'Ativa', tone: 'success' },
  conflict: { label: 'Em conflito', tone: 'danger' },
  superseded: { label: 'Substituída', tone: 'neutral' },
  rejected: { label: 'Rejeitada', tone: 'neutral' },
  expired: { label: 'Expirada', tone: 'neutral' },
};

export const KNOWLEDGE_KIND_LABELS: Record<KnowledgeKind, string> = {
  fact: 'Fato',
  decision: 'Decisão',
  insight: 'Insight',
};

export const KNOWLEDGE_STATUS: Record<KnowledgeStatus, { label: string; tone: StatusTone }> = {
  proposed: { label: 'Proposto', tone: 'warning' },
  active: { label: 'Ativo', tone: 'success' },
  rejected: { label: 'Rejeitado', tone: 'neutral' },
};

export const SOURCE_TYPE_LABELS: Record<SourceType, string> = {
  document: 'Documento',
  meeting: 'Reunião',
  website: 'Site',
  analytics: 'Analytics',
  review: 'Avaliação',
  social_post: 'Post em rede social',
  user_input: 'Entrada manual',
};

export const SOURCE_TRUST: Record<SourceTrust, { label: string; tone: StatusTone }> = {
  SYSTEM: { label: 'Sistema', tone: 'info' },
  APPROVED_CLIENT: { label: 'Aprovada pelo cliente', tone: 'success' },
  FIRST_PARTY: { label: 'Primária', tone: 'success' },
  TRUSTED_EXTERNAL: { label: 'Externa confiável', tone: 'info' },
  UNTRUSTED_EXTERNAL: { label: 'Externa não confiável', tone: 'danger' },
};

/** docs/02 §5: untrusted evidence never becomes a Fact, Decision or Rule (Insights may). */
export function canPromoteFrom(kind: KnowledgeKind | 'rule', trust: SourceTrust): boolean {
  return trust !== 'UNTRUSTED_EXTERNAL' || kind === 'insight';
}

export const CONTEXT_KIND_LABELS: Record<ContextKind, string> = {
  audience: 'Público',
  offer: 'Oferta',
  region: 'Região',
};

// ---------------------------------------------------------------------------
// Row schemas (PostgREST responses are validated before use)
// ---------------------------------------------------------------------------
const timestamp = z.string();
const nullableTimestamp = z.string().nullable();

export const brandProfileSchema = z.object({
  id: z.uuid(),
  business: z.string(),
  brand: z.string(),
  voice: z.string(),
  visual_references: z.array(z.string()),
  updated_at: timestamp,
});

const contextItemFields = {
  id: z.uuid(),
  name: z.string(),
  description: z.string(),
  status: z.enum(['active', 'archived']),
};
export const audienceSchema = z.object(contextItemFields);
export const regionSchema = z.object(contextItemFields);
export const offerSchema = z.object({
  ...contextItemFields,
  valid_from: z.string().nullable(),
  valid_until: z.string().nullable(),
});

export const sourceSchema = z.object({
  id: z.uuid(),
  type: z.enum(SOURCE_TYPES),
  title: z.string(),
  trust_level: z.enum(SOURCE_TRUST_LEVELS),
  uri: z.string().nullable(),
  created_at: timestamp,
});

export const factSchema = z.object({
  id: z.uuid(),
  source_id: z.uuid(),
  statement: z.string(),
  status: z.enum(KNOWLEDGE_STATUSES),
  valid_from: nullableTimestamp,
  valid_until: nullableTimestamp,
  created_at: timestamp,
});
export const decisionSchema = z.object({
  id: z.uuid(),
  source_id: z.uuid(),
  statement: z.string(),
  status: z.enum(KNOWLEDGE_STATUSES),
  rationale: z.string().nullable(),
  decided_at: timestamp,
  created_at: timestamp,
});
export const insightSchema = z.object({
  id: z.uuid(),
  source_id: z.uuid(),
  statement: z.string(),
  status: z.enum(KNOWLEDGE_STATUSES),
  confidence: z.number().nullable(),
  created_at: timestamp,
});

export const ruleSchema = z.object({
  id: z.uuid(),
  source_id: z.uuid(),
  type: z.enum(RULE_TYPES),
  subject: z.string().nullable(),
  statement: z.string(),
  scope_type: z.enum(RULE_SCOPES),
  channel: z.string().nullable(),
  priority: z.number().int(),
  status: z.enum(RULE_STATUSES),
  effective_from: nullableTimestamp,
  effective_until: nullableTimestamp,
  supersedes_rule_id: z.uuid().nullable(),
  created_at: timestamp,
});

export const effectiveRuleSchema = ruleSchema.pick({
  id: true,
  type: true,
  subject: true,
  statement: true,
  scope_type: true,
  channel: true,
  priority: true,
  effective_from: true,
  effective_until: true,
});

export type BrandProfile = z.infer<typeof brandProfileSchema>;
export type Audience = z.infer<typeof audienceSchema>;
export type Offer = z.infer<typeof offerSchema>;
export type Region = z.infer<typeof regionSchema>;
export type Source = z.infer<typeof sourceSchema>;
export type Rule = z.infer<typeof ruleSchema>;
export type EffectiveRule = z.infer<typeof effectiveRuleSchema>;

/** Facts, decisions and insights in one list, newest first. */
export interface KnowledgeItem {
  kind: KnowledgeKind;
  id: string;
  sourceId: string;
  statement: string;
  status: KnowledgeStatus;
  createdAt: string;
  validFrom: string | null;
  validUntil: string | null;
  detail: string | null;
}

/** Formats an ISO date or timestamp as dd/mm/aaaa (date part only, no timezone shift). */
export function formatDate(value: string | null): string | null {
  if (value === null) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  return match ? `${match[3]}/${match[2]}/${match[1]}` : null;
}

/**
 * Describes a validity window. Rules and facts use half-open windows `[from, until)` (TEST_SPEC
 * README); offers are stored as inclusive dates.
 */
export function formatValidity(
  from: string | null,
  until: string | null,
  end: 'exclusive' | 'inclusive' = 'exclusive',
): string | null {
  const start = formatDate(from);
  const finish = formatDate(until);
  if (start === null && finish === null) return null;
  const suffix = end === 'exclusive' ? ' (exclusivo)' : '';
  if (start !== null && finish !== null) return `${start} até ${finish}${suffix}`;
  return start !== null ? `a partir de ${start}` : `até ${finish ?? ''}${suffix}`;
}

export type ValidityState = 'current' | 'expired' | 'future';

/** Where `at` falls in the half-open window `[from, until)`; no bounds = always current. */
export function validityState(
  from: string | null,
  until: string | null,
  at: Date = new Date(),
): ValidityState {
  if (from !== null && at.getTime() < Date.parse(from)) return 'future';
  if (until !== null && at.getTime() >= Date.parse(until)) return 'expired';
  return 'current';
}

export const VALIDITY_STATES = ['current', 'expired', 'future'] as const;

export const VALIDITY: Record<ValidityState, { label: string; tone: StatusTone }> = {
  current: { label: 'Vigente', tone: 'success' },
  expired: { label: 'Fora da validade', tone: 'warning' },
  future: { label: 'Ainda não vigente', tone: 'info' },
};

/**
 * UTC offset used to turn a calendar date typed in a form into a timestamp. The agency operates in
 * America/Sao_Paulo, which has had no daylight saving time since 2019. Replace with a workspace
 * timezone when one exists.
 */
export const BUSINESS_UTC_OFFSET = '-03:00';

/** `2026-10-01` → `2026-10-01T00:00:00-03:00` (midnight in the business timezone). */
export function toBusinessTimestamp(date: string | null): string | null {
  return date === null ? null : `${date}T00:00:00${BUSINESS_UTC_OFFSET}`;
}
