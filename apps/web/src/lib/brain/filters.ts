import { isUuid } from '../identity/routing';
import {
  KNOWLEDGE_KINDS,
  KNOWLEDGE_STATUSES,
  RULE_SCOPES,
  RULE_STATUSES,
  RULE_TYPES,
  SOURCE_TRUST_LEVELS,
  VALIDITY_STATES,
  validityState,
  type KnowledgeItem,
  type KnowledgeKind,
  type KnowledgeStatus,
  type Rule,
  type RuleScope,
  type RuleStatus,
  type RuleType,
  type SourceTrust,
  type ValidityState,
} from './model';

/**
 * URL filters for the Knowledge and Rules pages (docs/07 §12: type, scope, status, source and
 * validity). Unknown values are ignored rather than rejected: filters only narrow what row level
 * security already allows.
 */

type SearchParams = Record<string, string | string[] | undefined>;

function first(params: SearchParams, key: string): string | undefined {
  const raw = params[key];
  return Array.isArray(raw) ? raw[0] : raw;
}

function pick<T extends string>(
  params: SearchParams,
  key: string,
  allowed: readonly T[],
): T | null {
  const value = first(params, key);
  return value !== undefined && (allowed as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

function pickUuid(params: SearchParams, key: string): string | null {
  const value = first(params, key);
  return value !== undefined && isUuid(value) ? value : null;
}

export interface KnowledgeFilters {
  kind: KnowledgeKind | null;
  status: KnowledgeStatus | null;
  trust: SourceTrust | null;
  source: string | null;
  validity: ValidityState | null;
}

export function parseKnowledgeFilters(params: SearchParams): KnowledgeFilters {
  return {
    kind: pick(params, 'kind', KNOWLEDGE_KINDS),
    status: pick(params, 'status', KNOWLEDGE_STATUSES),
    trust: pick(params, 'trust', SOURCE_TRUST_LEVELS),
    source: pickUuid(params, 'source'),
    validity: pick(params, 'validity', VALIDITY_STATES),
  };
}

/** Validity is computed from the window, so it is filtered after the query. */
export function filterKnowledgeByValidity(
  items: readonly KnowledgeItem[],
  validity: ValidityState | null,
  at: Date = new Date(),
): KnowledgeItem[] {
  if (validity === null) return [...items];
  return items.filter((item) => validityState(item.validFrom, item.validUntil, at) === validity);
}

export interface RuleFilters {
  type: RuleType | null;
  status: RuleStatus | null;
  scope: RuleScope | null;
  source: string | null;
  validity: ValidityState | null;
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
  return {
    type: pick(params, 'type', RULE_TYPES),
    status: pick(params, 'status', RULE_STATUSES),
    scope: pick(params, 'scope', RULE_SCOPES),
    source: pickUuid(params, 'source'),
    validity: pick(params, 'validity', VALIDITY_STATES),
    channel: normalizeChannel(first(params, 'channel')),
  };
}

export function filterRules(
  rules: readonly Rule[],
  filters: RuleFilters,
  at: Date = new Date(),
): Rule[] {
  return rules.filter(
    (rule) =>
      (filters.type === null || rule.type === filters.type) &&
      (filters.status === null || rule.status === filters.status) &&
      (filters.scope === null || rule.scope_type === filters.scope) &&
      (filters.source === null || rule.source_id === filters.source) &&
      (filters.validity === null ||
        validityState(rule.effective_from, rule.effective_until, at) === filters.validity),
  );
}
