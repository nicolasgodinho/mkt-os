'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { brainErrorMessage, isExpectedBrainError } from '@/lib/brain/errors';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { parseParticipants, toBusinessDateTime } from './model';

/**
 * Meeting actions: shape input, call the database API with the user's session. Capabilities,
 * tenancy, states and the proposed-first promotion are enforced by the database
 * (tests/acceptance/increment-4).
 */

const INVALID: ActionState = {
  status: 'error',
  message: 'Dados inválidos. Revise os campos e tente novamente.',
};

const scope = { workspaceSlug: z.string().refine(isSlug), clientId: z.uuid() };

const createForm = z.object({
  ...scope,
  title: z.string().trim().min(1).max(300),
  startsAt: z.string(),
  endsAt: z.string().optional(),
  participants: z.string().max(12000).optional(),
  recordingRef: z.string().trim().max(500).optional(),
});
const transcriptForm = z.object({
  ...scope,
  meetingId: z.uuid(),
  text: z.string().trim().min(1).max(500_000),
});
const jobForm = z.object({
  ...scope,
  meetingId: z.uuid(),
  decision: z.enum(['extract', 'transcribe']),
});
const proposalForm = z.object({
  ...scope,
  meetingId: z.uuid(),
  id: z.uuid(),
  decision: z.enum(['accept', 'reject']),
  statement: z.string().trim().max(2000).optional(),
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
  paths: string[],
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
    if (!isExpectedBrainError(error)) console.error(`meeting action failed: ${fn} (${error.code})`);
    return { ok: false, state: { status: 'error', message: brainErrorMessage(error) } };
  }
  for (const path of paths) revalidatePath(path);
  return { ok: true, data: result.data };
}

function meetingsPath(workspaceSlug: string, clientId: string): string {
  return `/w/${workspaceSlug}/clients/${clientId}/meetings`;
}

export async function createMeeting(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = createForm.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const form = parsed.data;
  const startsAt = toBusinessDateTime(form.startsAt);
  if (startsAt === null) return { status: 'error', message: 'Informe a data e a hora de início.' };
  const result = await call(
    'create_meeting',
    {
      p_client_id: form.clientId,
      p_title: form.title,
      p_starts_at: startsAt,
      p_ends_at: toBusinessDateTime(form.endsAt ?? null),
      p_participants: parseParticipants(form.participants ?? null),
      p_recording_ref: form.recordingRef === '' ? null : (form.recordingRef ?? null),
    },
    [meetingsPath(form.workspaceSlug, form.clientId)],
  );
  return result.ok ? { status: 'success', message: 'Reunião criada.' } : result.state;
}

export async function saveTranscript(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = transcriptForm.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const form = parsed.data;
  const base = meetingsPath(form.workspaceSlug, form.clientId);
  const result = await call(
    'save_meeting_transcript',
    { p_meeting_id: form.meetingId, p_text: form.text },
    [base, `${base}/${form.meetingId}`],
  );
  if (!result.ok) return result.state;
  return {
    status: 'success',
    message: `Transcrição salva (revisão ${String(result.data)}). Agora você pode extrair o conhecimento.`,
  };
}

export async function requestMeetingJob(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = jobForm.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const form = parsed.data;
  const base = meetingsPath(form.workspaceSlug, form.clientId);
  const result = await call(
    form.decision === 'extract' ? 'request_meeting_extraction' : 'request_meeting_transcription',
    { p_meeting_id: form.meetingId },
    [base, `${base}/${form.meetingId}`, `/w/${form.workspaceSlug}/automations`],
  );
  if (!result.ok) return result.state;
  return {
    status: 'success',
    message:
      'Enviado para a fila do AI Worker. O resultado aparece aqui quando o worker processar o job.',
  };
}

export async function reviewProposal(
  _previous: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = proposalForm.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const form = parsed.data;
  const base = meetingsPath(form.workspaceSlug, form.clientId);
  const brain = `/w/${form.workspaceSlug}/clients/${form.clientId}/brain`;
  const result =
    form.decision === 'accept'
      ? await call(
          'accept_meeting_proposal',
          { p_proposal_id: form.id, p_statement: form.statement ?? null },
          [`${base}/${form.meetingId}`, brain, `${brain}/knowledge`, `${brain}/rules`],
        )
      : await call('reject_meeting_proposal', { p_proposal_id: form.id }, [
          `${base}/${form.meetingId}`,
        ]);
  if (!result.ok) return result.state;
  return form.decision === 'accept'
    ? {
        status: 'success',
        message: 'Enviado ao Client Brain como proposta. A aprovação continua lá.',
      }
    : { status: 'success', message: 'Proposta rejeitada.' };
}
