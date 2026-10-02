'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { brainErrorMessage, isExpectedBrainError } from '@/lib/brain/errors';
import { toBusinessTimestamp } from '@/lib/brain/model';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { INITIATIVE_KINDS, INITIATIVE_STATUSES, RULE_CHECK_RESULTS, buildPayload } from './model';

/**
 * Content core actions: shape input and call the database API with the user's session. The
 * database enforces capabilities, tenancy, transitions, the Definition of Ready and the rule
 * validator (tests/acceptance/increment-5).
 */

const INVALID: ActionState = {
  status: 'error',
  message: 'Dados inválidos. Revise os campos e tente novamente.',
};

const scope = { workspaceSlug: z.string().refine(isSlug), clientId: z.uuid() };
const optional = z
  .string()
  .optional()
  .transform((value) => (value === undefined || value.trim() === '' ? null : value.trim()));

function values(formData: FormData): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === 'string') result[key] = value;
  }
  return result;
}

function contentBase(workspaceSlug: string, clientId: string): string {
  return `/w/${workspaceSlug}/clients/${clientId}/content`;
}

async function call(
  fn: string,
  args: Record<string, unknown>,
  workspaceSlug: string,
  clientId: string,
): Promise<{ ok: true; data: unknown } | { ok: false; state: ActionState }> {
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return {
      ok: false,
      state: { status: 'error', message: 'A autenticação não está configurada neste ambiente.' },
    };
  }
  const result = await supabase.rpc(fn, args);
  if (result.error !== null) {
    const error = { code: result.error.code, message: result.error.message };
    if (!isExpectedBrainError(error)) console.error(`content action failed: ${fn} (${error.code})`);
    return { ok: false, state: { status: 'error', message: brainErrorMessage(error) } };
  }
  revalidatePath(contentBase(workspaceSlug, clientId), 'layout');
  return { ok: true, data: result.data };
}

const success = (message: string): ActionState => ({ status: 'success', message });

export async function createInitiative(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({
      ...scope,
      kind: z.enum(INITIATIVE_KINDS),
      name: z.string().trim().min(1).max(200),
      startAt: optional,
      endAt: optional,
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'create_initiative',
    {
      p_client_id: f.clientId,
      p_kind: f.kind,
      p_name: f.name,
      p_start_at: f.startAt,
      p_end_at: f.endAt,
    },
    f.workspaceSlug,
    f.clientId,
  );
  return r.ok ? success('Iniciativa criada.') : r.state;
}

export async function setInitiativeStatus(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = z
    .object({ ...scope, id: z.uuid(), decision: z.enum(INITIATIVE_STATUSES) })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'set_initiative_status',
    { p_initiative_id: f.id, p_status: f.decision },
    f.workspaceSlug,
    f.clientId,
  );
  return r.ok ? success('Status atualizado.') : r.state;
}

export async function createOpportunity(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({
      ...scope,
      type: z.string().trim().min(1).max(40),
      title: z.string().trim().min(1).max(300),
      reason: z.string().trim().min(1).max(4000),
      expiresAt: optional,
      sourceId: optional,
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'create_opportunity',
    {
      p_client_id: f.clientId,
      p_type: f.type.toLowerCase().replace(/[^a-z0-9_]/g, '_'),
      p_title: f.title,
      p_reason: f.reason,
      p_expires_at: toBusinessTimestamp(f.expiresAt),
      p_evidence_refs: f.sourceId === null ? [] : [f.sourceId],
    },
    f.workspaceSlug,
    f.clientId,
  );
  return r.ok ? success('Oportunidade registrada.') : r.state;
}

export async function reviewOpportunity(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({ ...scope, id: z.uuid(), decision: z.enum(['watch', 'dismiss', 'convert']) })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r =
    f.decision === 'convert'
      ? await call('convert_opportunity', { p_opportunity_id: f.id }, f.workspaceSlug, f.clientId)
      : await call(
          'review_opportunity',
          { p_opportunity_id: f.id, p_decision: f.decision },
          f.workspaceSlug,
          f.clientId,
        );
  if (!r.ok) return r.state;
  return success(
    f.decision === 'convert'
      ? 'Virou pauta. Complete o Definition of Ready na pauta.'
      : f.decision === 'watch'
        ? 'Acompanhando.'
        : 'Descartada.',
  );
}

export async function createPauta(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({ ...scope, title: z.string().trim().min(1).max(300), initiativeId: optional })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'create_pauta',
    { p_client_id: f.clientId, p_title: f.title, p_initiative_id: f.initiativeId },
    f.workspaceSlug,
    f.clientId,
  );
  return r.ok ? success('Pauta criada.') : r.state;
}

const pautaForm = z.object({
  ...scope,
  id: z.uuid(),
  decision: z.enum(['save', 'ready']).optional(),
  objective: z.string().max(2000).optional(),
  audienceIds: z.string().optional(),
  pillar: z.string().max(200).optional(),
  angle: z.string().max(2000).optional(),
  message: z.string().max(2000).optional(),
  cta: z.string().max(300).optional(),
  offerId: z.string().optional(),
  mandatories: z.string().max(4000).optional(),
  constraints: z.string().max(4000).optional(),
});

export async function savePauta(_p: ActionState, formData: FormData): Promise<ActionState> {
  const raw = values(formData);
  const parsed = pautaForm.safeParse(raw);
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const audienceIds = formData
    .getAll('audienceIds')
    .filter((value): value is string => typeof value === 'string' && value !== '');
  const fields = {
    objective: f.objective ?? '',
    audience_ids: audienceIds,
    pillar: f.pillar ?? '',
    angle: f.angle ?? '',
    message: f.message ?? '',
    cta: f.cta ?? '',
    offer_id: f.offerId === undefined || f.offerId === '' ? null : f.offerId,
    mandatories: f.mandatories ?? '',
    constraints: f.constraints ?? '',
  };
  const saved = await call(
    'update_pauta',
    { p_pauta_id: f.id, p_fields: fields },
    f.workspaceSlug,
    f.clientId,
  );
  if (!saved.ok) return saved.state;
  if (f.decision !== 'ready') return success('Pauta salva.');
  const ready = await call('mark_pauta_ready', { p_pauta_id: f.id }, f.workspaceSlug, f.clientId);
  return ready.ok ? success('Pauta pronta para produção.') : ready.state;
}

export async function createContent(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({
      ...scope,
      pautaId: z.uuid(),
      channel: z.string().trim().min(1).max(40),
      format: z.string().trim().min(1).max(40),
      title: z.string().trim().min(1).max(300),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'create_content',
    { p_pauta_id: f.pautaId, p_channel: f.channel, p_format: f.format, p_title: f.title },
    f.workspaceSlug,
    f.clientId,
  );
  return r.ok ? success('Conteúdo criado.') : r.state;
}

export async function saveContent(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({
      ...scope,
      id: z.uuid(),
      decision: z.enum(['save', 'submit']).optional(),
      headline: z.string().max(500).optional(),
      body: z.string().max(10000).optional(),
      cta: z.string().max(300).optional(),
      hashtags: z.string().max(4000).optional(),
      alt_text: z.string().max(2000).optional(),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const saved = await call(
    'save_content_payload',
    { p_content_id: f.id, p_payload: buildPayload(f) },
    f.workspaceSlug,
    f.clientId,
  );
  if (!saved.ok) return saved.state;
  if (f.decision !== 'submit') return success('Rascunho salvo.');
  const submitted = await call(
    'submit_for_internal_review',
    { p_content_id: f.id },
    f.workspaceSlug,
    f.clientId,
  );
  return submitted.ok
    ? success('Revisão criada e enviada para a revisão interna.')
    : submitted.state;
}

export async function recordRuleCheck(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({
      ...scope,
      revisionId: z.uuid(),
      ruleId: z.uuid(),
      decision: z.enum(RULE_CHECK_RESULTS),
      note: z.string().max(1000).optional(),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'record_rule_check',
    {
      p_revision_id: f.revisionId,
      p_rule_id: f.ruleId,
      p_result: f.decision,
      p_note: f.note?.trim() ? f.note.trim() : null,
    },
    f.workspaceSlug,
    f.clientId,
  );
  return r.ok ? success('Checagem registrada.') : r.state;
}

export async function completeReview(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z
    .object({
      ...scope,
      revisionId: z.uuid(),
      decision: z.enum(['approve', 'changes']),
      note: z.string().max(500).optional(),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const r = await call(
    'complete_internal_review',
    { p_revision_id: f.revisionId, p_decision: f.decision, p_note: f.note ?? null },
    f.workspaceSlug,
    f.clientId,
  );
  if (!r.ok) return r.state;
  return f.decision === 'approve'
    ? success('Revisão aprovada internamente.')
    : success('Alterações solicitadas: o conteúdo voltou para produção.');
}
