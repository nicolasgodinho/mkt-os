'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { calendarErrorMessage } from './errors';
import { toBusinessDateTime, toBusinessEndOfDay } from './model';

/**
 * Publication and deadline actions. They shape input and call the database API with the user's
 * session; who may schedule, publish and plan is enforced by the database
 * (tests/acceptance/increment-7).
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
const scopeSchema = z.object({
  workspaceSlug: z.string().refine(isSlug),
  clientId: z.uuid(),
  contentId: z.uuid(),
});

function pathsFor(scope: z.infer<typeof scopeSchema>): string[] {
  return [
    `/w/${scope.workspaceSlug}/calendar`,
    `/w/${scope.workspaceSlug}/clients/${scope.clientId}/content/items/${scope.contentId}`,
    `/portal/${scope.clientId}`,
    `/portal/${scope.clientId}/calendar`,
  ];
}

const dateTimeSchema = z
  .string()
  .transform((value) => toBusinessDateTime(value))
  .refine((value) => value !== null);

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
      console.error(`calendar action failed: ${fn} (${error.code})`);
    }
    return {
      status: 'error',
      message: calendarErrorMessage({ code: error.code, message: error.message }),
    };
  }
  for (const path of paths) revalidatePath(path);
  return null;
}

export async function schedulePublication(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = scopeSchema
    .extend({ scheduledAt: dateTimeSchema, channel: z.string().trim().optional() })
    .safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Informe data e hora da publicação.' };
  const f = parsed.data;
  const failure = await call(
    'schedule_publication',
    {
      p_content_id: f.contentId,
      p_scheduled_at: f.scheduledAt,
      p_channel: f.channel === undefined || f.channel === '' ? null : f.channel,
    },
    pathsFor(f),
  );
  return failure ?? { status: 'success', message: 'Publicação agendada.' };
}

export async function reschedulePublication(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = scopeSchema
    .extend({ publicationId: z.uuid(), scheduledAt: dateTimeSchema })
    .safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Informe a nova data e hora.' };
  const f = parsed.data;
  const failure = await call(
    'reschedule_publication',
    { p_publication_id: f.publicationId, p_scheduled_at: f.scheduledAt },
    pathsFor(f),
  );
  return failure ?? { status: 'success', message: 'Data de publicação alterada.' };
}

export async function cancelPublication(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = scopeSchema.extend({ publicationId: z.uuid() }).safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call(
    'cancel_publication',
    { p_publication_id: f.publicationId },
    pathsFor(f),
  );
  return failure ?? { status: 'success', message: 'Publicação cancelada.' };
}

export async function markPublished(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = scopeSchema
    .extend({ publicationId: z.uuid(), remoteUrl: z.string().trim().max(2000).optional() })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call(
    'mark_publication_published',
    {
      p_publication_id: f.publicationId,
      p_remote_url: f.remoteUrl === undefined || f.remoteUrl === '' ? null : f.remoteUrl,
    },
    pathsFor(f),
  );
  return failure ?? { status: 'success', message: 'Publicação registrada.' };
}

export async function setProductionDeadline(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = scopeSchema
    .extend({
      dueAt: z
        .union([z.literal(''), z.iso.date()])
        .optional()
        .transform((value) => (value === undefined || value === '' ? null : value)),
    })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call(
    'set_production_deadline',
    { p_content_id: f.contentId, p_due_at: toBusinessEndOfDay(f.dueAt) },
    pathsFor(f),
  );
  return (
    failure ?? {
      status: 'success',
      message: f.dueAt === null ? 'Prazo de produção removido.' : 'Prazo de produção definido.',
    }
  );
}
