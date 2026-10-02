'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { toBusinessTimestamp } from '@/lib/brain/model';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { collabErrorMessage } from './errors';

/**
 * Client approval and comment actions. They shape input and call the database API with the user's
 * session; who may request, decide and comment is enforced by the database
 * (tests/acceptance/increment-6).
 */

const INVALID: ActionState = { status: 'error', message: 'Dados inválidos.' };

function values(formData: FormData): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === 'string') result[key] = value;
  }
  return result;
}

/** Paths are rebuilt from validated ids only, never taken from the form. */
const pathSchema = z.object({
  workspaceSlug: z.string().refine(isSlug).optional(),
  clientId: z.uuid(),
  contentId: z.uuid().optional(),
  requestId: z.uuid().optional(),
});

function pathsFor(scope: z.infer<typeof pathSchema>): string[] {
  const paths = [`/portal/${scope.clientId}`, `/portal/${scope.clientId}/approvals`];
  if (scope.requestId !== undefined) {
    paths.push(`/portal/${scope.clientId}/approvals/${scope.requestId}`);
  }
  if (scope.workspaceSlug !== undefined) {
    paths.push(`/w/${scope.workspaceSlug}/approvals`);
    if (scope.contentId !== undefined) {
      paths.push(
        `/w/${scope.workspaceSlug}/clients/${scope.clientId}/content/items/${scope.contentId}`,
      );
    }
  }
  return paths;
}

async function call(
  fn: string,
  args: Record<string, unknown>,
  paths: string[],
): Promise<ActionState | null> {
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return { status: 'error', message: 'A autenticação não está configurada neste ambiente.' };
  }
  const { error } = await supabase.rpc(fn, args);
  if (error !== null) {
    if (!['42501', 'P0002', '22023'].includes(error.code)) {
      console.error(`collaboration action failed: ${fn} (${error.code})`);
    }
    return {
      status: 'error',
      message: collabErrorMessage({ code: error.code, message: error.message }),
    };
  }
  for (const path of paths) revalidatePath(path);
  return null;
}

export async function requestClientApproval(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = pathSchema
    .extend({
      revisionId: z.uuid(),
      dueAt: z
        .string()
        .optional()
        .transform((value) => (value === undefined || value === '' ? null : value)),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call(
    'request_client_approval',
    { p_revision_id: f.revisionId, p_due_at: toBusinessTimestamp(f.dueAt) },
    pathsFor(f),
  );
  return failure ?? { status: 'success', message: 'Enviado para aprovação do cliente.' };
}

export async function cancelApprovalRequest(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = pathSchema.extend({ requestId: z.uuid() }).safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call('cancel_approval_request', { p_request_id: f.requestId }, pathsFor(f));
  return failure ?? { status: 'success', message: 'Pedido de aprovação cancelado.' };
}

export async function decideApproval(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = pathSchema
    .extend({
      requestId: z.uuid(),
      decision: z.enum(['approve', 'changes']),
      comment: z.string().max(4000).optional(),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call(
    'decide_approval',
    {
      p_request_id: f.requestId,
      p_decision: f.decision,
      p_comment: f.comment?.trim() ? f.comment.trim() : null,
    },
    pathsFor(f),
  );
  if (failure !== null) return failure;
  return f.decision === 'approve'
    ? { status: 'success', message: 'Aprovado. Obrigado!' }
    : { status: 'success', message: 'Pedido de alterações enviado para a equipe.' };
}

export async function addComment(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = pathSchema
    .extend({
      contentId: z.uuid(),
      body: z.string().trim().min(1).max(4000),
      decision: z.enum(['internal', 'client']).optional(),
    })
    .safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Escreva um comentário.' };
  const f = parsed.data;
  const failure = await call(
    'add_comment',
    {
      p_target_type: 'content',
      p_target_id: f.contentId,
      p_body: f.body,
      p_visibility: f.decision ?? 'client',
    },
    pathsFor(f),
  );
  return failure ?? { status: 'success', message: 'Comentário enviado.' };
}
