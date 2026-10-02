import 'server-only';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  contentSchema,
  initiativeSchema,
  opportunitySchema,
  pautaSchema,
  revisionSchema,
  validationSchema,
  type Content,
  type Initiative,
  type Opportunity,
  type Pauta,
  type Revision,
  type ValidationRow,
} from './model';

/** Content core reads with the user's session: RLS returns rows to internal staff only. */

class ContentDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`content data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'ContentDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new ContentDataError('client unavailable', 'not_configured');
  return supabase;
}

const PAUTA_COLUMNS =
  'id, title, status, initiative_id, opportunity_id, objective, audience_ids, pillar, angle, message, cta, offer_id, source_ids, mandatories, constraints, created_at';
const CONTENT_COLUMNS =
  'id, pauta_id, channel, format, title, status, working_payload, current_revision_id, approved_revision_id, updated_at';

export async function listInitiatives(clientId: string): Promise<Initiative[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('initiatives')
    .select('id, kind, name, status, paused_from, start_at, end_at')
    .eq('client_id', clientId)
    .order('created_at', { ascending: false });
  if (error !== null) throw new ContentDataError('initiatives', error.code);
  return z.array(initiativeSchema).parse(data);
}

export async function listOpportunities(clientId: string): Promise<Opportunity[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('opportunities')
    .select('id, type, title, reason, status, confidence, expires_at, evidence_refs, created_at')
    .eq('client_id', clientId)
    .order('created_at', { ascending: false })
    .limit(100);
  if (error !== null) throw new ContentDataError('opportunities', error.code);
  return z.array(opportunitySchema).parse(data);
}

export async function listPautas(clientId: string): Promise<Pauta[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('pautas')
    .select(PAUTA_COLUMNS)
    .eq('client_id', clientId)
    .order('created_at', { ascending: false })
    .limit(200);
  if (error !== null) throw new ContentDataError('pautas', error.code);
  return z.array(pautaSchema).parse(data);
}

export async function getPauta(clientId: string, pautaId: string): Promise<Pauta | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('pautas')
    .select(PAUTA_COLUMNS)
    .eq('client_id', clientId)
    .eq('id', pautaId)
    .maybeSingle();
  if (error !== null) throw new ContentDataError('pauta', error.code);
  return data === null ? null : pautaSchema.parse(data);
}

export async function getPautaReadiness(pautaId: string): Promise<Map<string, boolean>> {
  const supabase = await reader();
  const result = await supabase.rpc('pauta_readiness', { p_pauta_id: pautaId });
  if (result.error !== null) throw new ContentDataError('readiness', result.error.code);
  const rows = z.array(z.object({ field: z.string(), ok: z.boolean() })).parse(result.data);
  return new Map(rows.map((row) => [row.field, row.ok]));
}

export async function listContents(clientId: string, pautaId?: string): Promise<Content[]> {
  const supabase = await reader();
  let query = supabase.from('contents').select(CONTENT_COLUMNS).eq('client_id', clientId);
  if (pautaId !== undefined) query = query.eq('pauta_id', pautaId);
  const { data, error } = await query.order('updated_at', { ascending: false }).limit(200);
  if (error !== null) throw new ContentDataError('contents', error.code);
  return z.array(contentSchema).parse(data);
}

export async function getContent(clientId: string, contentId: string): Promise<Content | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('contents')
    .select(CONTENT_COLUMNS)
    .eq('client_id', clientId)
    .eq('id', contentId)
    .maybeSingle();
  if (error !== null) throw new ContentDataError('content', error.code);
  return data === null ? null : contentSchema.parse(data);
}

export async function listRevisions(contentId: string): Promise<Revision[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('content_revisions')
    .select('id, revision_number, payload, immutable_hash, created_at')
    .eq('content_id', contentId)
    .order('revision_number', { ascending: false });
  if (error !== null) throw new ContentDataError('revisions', error.code);
  return z.array(revisionSchema).parse(data);
}

export async function getRevisionValidation(revisionId: string): Promise<ValidationRow[]> {
  const supabase = await reader();
  const result = await supabase.rpc('revision_validation', { p_revision_id: revisionId });
  if (result.error !== null) throw new ContentDataError('validation', result.error.code);
  return z.array(validationSchema).parse(result.data);
}
