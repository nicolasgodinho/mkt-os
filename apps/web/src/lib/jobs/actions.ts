'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { jobErrorMessage } from './errors';

/**
 * Job center actions. They only shape input and call the database API with the user's session;
 * `workspace.manage`, visibility and allowed states are enforced by the database
 * (tests/acceptance/increment-3).
 */

const INVALID: ActionState = { status: 'error', message: 'Dados inválidos.' };

const requestForm = z.object({
  workspaceSlug: z.string().refine(isSlug),
  workspaceId: z.uuid(),
  type: z.enum(['system.healthcheck', 'ai.model_check']),
  // One key per rendered form: a double submit of the same form never enqueues twice.
  idempotencyKey: z.string().trim().min(1).max(200),
});

const jobForm = z.object({
  workspaceSlug: z.string().refine(isSlug),
  id: z.uuid(),
  decision: z.enum(['cancel', 'retry']),
});

function values(formData: FormData): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === 'string') result[key] = value;
  }
  return result;
}

async function call(
  fn: string,
  args: Record<string, unknown>,
  workspaceSlug: string,
): Promise<ActionState | null> {
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return { status: 'error', message: 'A autenticação não está configurada neste ambiente.' };
  }
  const { error } = await supabase.rpc(fn, args);
  if (error !== null) {
    if (!['42501', 'P0002', '22023', '23505'].includes(error.code)) {
      console.error(`job center action failed: ${fn} (${error.code})`);
    }
    return { status: 'error', message: jobErrorMessage({ code: error.code }) };
  }
  revalidatePath(`/w/${workspaceSlug}/automations`);
  return null;
}

export async function requestSystemJob(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = requestForm.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const form = parsed.data;
  const failure = await call(
    'request_system_job',
    { p_workspace_id: form.workspaceId, p_type: form.type, p_idempotency_key: form.idempotencyKey },
    form.workspaceSlug,
  );
  return failure ?? { status: 'success', message: 'Job enviado para a fila.' };
}

export async function manageJob(_previous: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = jobForm.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const form = parsed.data;
  const failure = await call(
    form.decision === 'cancel' ? 'cancel_job' : 'retry_job',
    { p_job_id: form.id },
    form.workspaceSlug,
  );
  return (
    failure ?? {
      status: 'success',
      message: form.decision === 'cancel' ? 'Job cancelado.' : 'Job reenviado para a fila.',
    }
  );
}
