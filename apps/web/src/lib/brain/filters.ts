import {
  KNOWLEDGE_KINDS,
  KNOWLEDGE_STATUSES,
  RULE_SCOPES,
  RULE_STATUSES,
  RULE_TYPES,
  SOURCE_TRUST_LEVELS,
  type KnowledgeKind,
  type KnowledgeStatus,
  type RuleScope,
  type RuleStatus,
  type Rule,
  type RuleType,
  type SourceTrust,
} from './model';

/**
 * URL filters for the Knowledge and Rules pages (docs/07 §12). Unknown values are ignored rather
 * than rejected: filters only narrow what row level security already allows.
 */

type SearchParams = Record<string, string | string[] | undefined>;

function pick<T extends string>(
  params: SearchParams,
  key: string,
  allowed: readonly T[],
): T | null {
  const raw = params[key];
  const value = Array.isArray(raw) ? raw[0] : raw;
  return value !== undefined && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

export interface KnowledgeFilters {
  kind: KnowledgeKind | null;
  status: KnowledgeStatus | null;
  trust: SourceTrust | null;
}

export function parseKnowledgeFilters(params: SearchParams): KnowledgeFilters {
  return {
    kind: pick(params, 'kind', KNOWLEDGE_KINDS),
    status: pick(params, 'status', KNOWLEDGE_STATUSES),
    trust: pick(params, 'trust', SOURCE_TRUST_LEVELS),
  };
}

export interface RuleFilters {
  type: RuleType | null;
  status: RuleStatus | null;
  scope: RuleScope | null;
  /** Channel for the effective-rules preview; null = client scope only. */
  channel: string | null;
}

const CHANNEL_KEY = /^[a-z0-9][a-z0-9_-]{0,39}$/;

/** Same normalization as the database: trimmed, lowercased, restricted alphabet. */
export function normalizeChannel(value: string | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  const channel = value.trim().toLowerCase();
  return CHANNEL_KEY.test(channel) ? channel : null;
}

export function parseRuleFilters(params: SearchParams): RuleFilters {
  const rawChannel = params.channel;
  return {
    type: pick(params, 'type', RULE_TYPES),
    status: pick(params, 'status', RULE_STATUSES),
    scope: pick(params, 'scope', RULE_SCOPES),
    channel: normalizeChannel(Array.isArray(rawChannel) ? rawChannel[0] : rawChannel),
  };
}

export function filterRules(rules: readonly Rule[], filters: RuleFilters): Rule[] {
  return rules.filter(
    (rule) =>
      (filters.type === null || rule.type === filters.type) &&
      (filters.status === null || rule.status === filters.status) &&
      (filters.scope === null || rule.scope_type === filters.scope),
  );
}
