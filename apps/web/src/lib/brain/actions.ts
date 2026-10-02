'use server';

import { revalidatePath } from 'next/cache';
import type { z } from 'zod';
import { createSupabaseWriter } from '@/lib/supabase/server';
import type { ActionState } from '@/lib/action-state';
import { brainErrorMessage, isExpectedBrainError } from './errors';
import { toBusinessTimestamp } from './model';
import {
  archiveContextItemForm,
  brandProfileForm,
  contextItemForm,
  formValues,
  knowledgeForm,
  reviewKnowledgeForm,
  reviewRuleForm,
  ruleForm,
  sourceForm,
  type scopeSchema,
} from './form-data';

/**
 * Client Brain server actions. They only shape input and call the database API with the
 * signed-in user's session: authorization, tenancy, trust and state rules are enforced by the
 * SECURITY DEFINER functions (tests/acceptance/increment-2), never here.
 */

type Scope = z.infer<typeof scopeSchema>;

const INVALID_FORM: ActionState = {
  status: 'error',
  message: 'Dados inválidos. Revise os campos e tente novamente.',
};

async function callRpc(
  fn: string,
  args: Record<string, unknown>,
  scope: Scope,
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
    if (!isExpectedBrainError(error)) {
      console.error(`client brain action failed: ${fn} (${error.code})`);
    }
    return { ok: false, state: { status: 'error', message: brainErrorMessage(error) } };
  }
  revalidatePath(`/w/${scope.workspaceSlug}/clients/${scope.clientId}/brain`, 'layout');
  return { ok: true, data: result.data };
}

function success(message: string): ActionState {
  return { status: 'success', message };
}

export async function saveBrandProfile(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = brandProfileForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const result = await callRpc(
    'save_brand_profile',
    {
      p_client_id: form.clientId,
      p_business: form.business,
      p_brand: form.brand,
      p_voice: form.voice,
      p_visual_references: form.visualReferences,
    },
    form,
  );
  return result.ok ? success('Perfil da marca salvo.') : result.state;
}

export async function saveContextItem(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = contextItemForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const common = {
    p_client_id: form.clientId,
    p_name: form.name,
    p_description: form.description,
  };
  const result =
    form.kind === 'audience'
      ? await callRpc('save_audience', { ...common, p_audience_id: form.id }, form)
      : form.kind === 'region'
        ? await callRpc('save_region', { ...common, p_region_id: form.id }, form)
        : await callRpc(
            'save_offer',
            {
              ...common,
              p_offer_id: form.id,
              p_valid_from: form.validFrom,
              p_valid_until: form.validUntil,
            },
            form,
          );
  return result.ok ? success('Salvo.') : result.state;
}

export async function archiveContextItem(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = archiveContextItemForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const result = await callRpc('archive_context_item', { p_kind: form.kind, p_id: form.id }, form);
  return result.ok ? success('Arquivado.') : result.state;
}

export async function createSource(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = sourceForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const result = await callRpc(
    'create_source',
    {
      p_client_id: form.clientId,
      p_type: form.type,
      p_title: form.title,
      p_trust_level: form.trustLevel,
      p_uri: form.uri,
    },
    form,
  );
  return result.ok ? success('Fonte registrada.') : result.state;
}

export async function proposeKnowledge(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = knowledgeForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const common = {
    p_client_id: form.clientId,
    p_source_id: form.sourceId,
    p_statement: form.statement,
  };
  const result =
    form.kind === 'fact'
      ? await callRpc(
          'propose_fact',
          {
            ...common,
            p_valid_from: toBusinessTimestamp(form.validFrom),
            p_valid_until: toBusinessTimestamp(form.validUntil),
          },
          form,
        )
      : form.kind === 'decision'
        ? await callRpc(
            'propose_decision',
            {
              ...common,
              p_rationale: form.rationale,
              ...(form.decidedAt === null
                ? {}
                : { p_decided_at: toBusinessTimestamp(form.decidedAt) }),
            },
            form,
          )
        : await callRpc('propose_insight', { ...common, p_confidence: form.confidence }, form);
  return result.ok ? success('Proposto. Aguarda aprovação.') : result.state;
}

export async function reviewKnowledge(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = reviewKnowledgeForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const result = await callRpc(
    form.decision === 'approve' ? 'approve_knowledge' : 'reject_knowledge',
    { p_kind: form.kind, p_id: form.id },
    form,
  );
  if (!result.ok) return result.state;
  return success(form.decision === 'approve' ? 'Aprovado.' : 'Rejeitado.');
}

export async function proposeRule(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = ruleForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const result = await callRpc(
    'propose_rule',
    {
      p_client_id: form.clientId,
      p_source_id: form.sourceId,
      p_type: form.type,
      p_subject: form.subject,
      p_statement: form.statement,
      p_channel: form.channel,
      p_priority: form.priority,
      p_effective_from: toBusinessTimestamp(form.effectiveFrom),
      p_effective_until: toBusinessTimestamp(form.effectiveUntil),
      p_supersedes_rule_id: form.supersedesRuleId,
    },
    form,
  );
  return result.ok ? success('Regra proposta. Aguarda ativação.') : result.state;
}

export async function reviewRule(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = reviewRuleForm.safeParse(formValues(formData));
  if (!parsed.success) return INVALID_FORM;
  const form = parsed.data;
  const result = await callRpc(
    form.decision === 'activate' ? 'activate_rule' : 'reject_rule',
    { p_rule_id: form.id },
    form,
  );
  if (!result.ok) return result.state;
  if (form.decision === 'reject') return success('Regra rejeitada.');
  return result.data === 'conflict'
    ? {
        status: 'warning',
        message:
          'A regra entrou em conflito com outra regra ativa. As duas ficam fora das regras efetivas até alguém resolver o conflito.',
      }
    : success('Regra ativada.');
}
