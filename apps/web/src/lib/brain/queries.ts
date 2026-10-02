import 'server-only';
import { cache } from 'react';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import type { KnowledgeFilters } from './filters';
import {
  audienceSchema,
  brandProfileSchema,
  decisionSchema,
  effectiveRuleSchema,
  factSchema,
  insightSchema,
  offerSchema,
  regionSchema,
  ruleSchema,
  sourceSchema,
  type Audience,
  type BrandProfile,
  type EffectiveRule,
  type KnowledgeItem,
  type Offer,
  type Region,
  type Rule,
  type Source,
} from './model';

/**
 * Client Brain reads. Every query runs with the signed-in user's session: row level security
 * returns rows only to internal staff with access to the client (internal-only, decision 3).
 * Filters narrow results; they never grant access.
 */

class BrainDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`client brain data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'BrainDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new BrainDataError('client unavailable', 'not_configured');
  return supabase;
}

export const getBrandProfile = cache(async (clientId: string): Promise<BrandProfile | null> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('brand_profiles')
    .select('id, business, brand, voice, visual_references, updated_at')
    .eq('client_id', clientId)
    .maybeSingle();
  if (error !== null) throw new BrainDataError('brand profile', error.code);
  return data === null ? null : brandProfileSchema.parse(data);
});

export const listAudiences = cache(async (clientId: string): Promise<Audience[]> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('audiences')
    .select('id, name, description, status')
    .eq('client_id', clientId)
    .order('status')
    .order('name');
  if (error !== null) throw new BrainDataError('audiences', error.code);
  return z.array(audienceSchema).parse(data);
});

export const listOffers = cache(async (clientId: string): Promise<Offer[]> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('offers')
    .select('id, name, description, status, valid_from, valid_until')
    .eq('client_id', clientId)
    .order('status')
    .order('name');
  if (error !== null) throw new BrainDataError('offers', error.code);
  return z.array(offerSchema).parse(data);
});

export const listRegions = cache(async (clientId: string): Promise<Region[]> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('regions')
    .select('id, name, description, status')
    .eq('client_id', clientId)
    .order('status')
    .order('name');
  if (error !== null) throw new BrainDataError('regions', error.code);
  return z.array(regionSchema).parse(data);
});

export const listSources = cache(async (clientId: string): Promise<Source[]> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('sources')
    .select('id, type, title, trust_level, uri, created_at')
    .eq('client_id', clientId)
    .order('created_at', { ascending: false })
    .order('title')
    .order('id');
  if (error !== null) throw new BrainDataError('sources', error.code);
  return z.array(sourceSchema).parse(data);
});

function formatConfidence(confidence: number | null): string | null {
  return confidence === null ? null : `Confiança ${Math.round(confidence * 100).toString()}%`;
}

export async function listKnowledge(
  clientId: string,
  filters: KnowledgeFilters,
  sources: readonly Source[],
): Promise<KnowledgeItem[]> {
  const supabase = await reader();
  const narrowed = sources.filter(
    (source) =>
      (filters.trust === null || source.trust_level === filters.trust) &&
      (filters.source === null || source.id === filters.source),
  );
  const sourceIds =
    filters.trust === null && filters.source === null ? null : narrowed.map((s) => s.id);
  if (sourceIds !== null && sourceIds.length === 0) return [];

  const wants = (kind: KnowledgeItem['kind']) => filters.kind === null || filters.kind === kind;
  const select = async (table: 'facts' | 'decisions' | 'insights', columns: string) => {
    let query = supabase.from(table).select(columns).eq('client_id', clientId);
    if (filters.status !== null) query = query.eq('status', filters.status);
    if (sourceIds !== null) query = query.in('source_id', sourceIds);
    const { data, error } = await query;
    if (error !== null) throw new BrainDataError(table, error.code);
    return data as unknown;
  };

  const items: KnowledgeItem[] = [];
  if (wants('fact')) {
    const rows = await select(
      'facts',
      'id, source_id, statement, status, valid_from, valid_until, created_at',
    );
    for (const fact of z.array(factSchema).parse(rows)) {
      items.push({
        kind: 'fact',
        id: fact.id,
        sourceId: fact.source_id,
        statement: fact.statement,
        status: fact.status,
        createdAt: fact.created_at,
        validFrom: fact.valid_from,
        validUntil: fact.valid_until,
        detail: null,
      });
    }
  }
  if (wants('decision')) {
    const rows = await select(
      'decisions',
      'id, source_id, statement, status, rationale, decided_at, created_at',
    );
    for (const decision of z.array(decisionSchema).parse(rows)) {
      items.push({
        kind: 'decision',
        id: decision.id,
        sourceId: decision.source_id,
        statement: decision.statement,
        status: decision.status,
        createdAt: decision.created_at,
        validFrom: null,
        validUntil: null,
        detail: decision.rationale,
      });
    }
  }
  if (wants('insight')) {
    const rows = await select(
      'insights',
      'id, source_id, statement, status, confidence, created_at',
    );
    for (const insight of z.array(insightSchema).parse(rows)) {
      items.push({
        kind: 'insight',
        id: insight.id,
        sourceId: insight.source_id,
        statement: insight.statement,
        status: insight.status,
        createdAt: insight.created_at,
        validFrom: null,
        validUntil: null,
        detail: formatConfidence(insight.confidence),
      });
    }
  }
  return items.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

/** Every rule of the client (any status); pages filter in memory with `filterRules`. */
export const listRules = cache(async (clientId: string): Promise<Rule[]> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('rules')
    .select(
      'id, source_id, type, subject, statement, scope_type, channel, priority, status, effective_from, effective_until, supersedes_rule_id, created_at',
    )
    .eq('client_id', clientId)
    .order('subject', { nullsFirst: false })
    .order('created_at', { ascending: false });
  if (error !== null) throw new BrainDataError('rules', error.code);
  return z.array(ruleSchema).parse(data);
});

export async function listEffectiveRules(
  clientId: string,
  channel: string | null,
): Promise<EffectiveRule[]> {
  const supabase = await reader();
  const result = await supabase.rpc('effective_rules', {
    p_client_id: clientId,
    p_channel: channel,
  });
  if (result.error !== null) throw new BrainDataError('effective rules', result.error.code);
  return z.array(effectiveRuleSchema.loose()).parse(result.data);
}

export const listRuleConflicts = cache(async (clientId: string): Promise<EffectiveRule[]> => {
  const supabase = await reader();
  const result = await supabase.rpc('rule_conflicts', { p_client_id: clientId });
  if (result.error !== null) throw new BrainDataError('rule conflicts', result.error.code);
  return z.array(effectiveRuleSchema.loose()).parse(result.data);
});
