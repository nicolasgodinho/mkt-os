'use server';

import { revalidatePath } from 'next/cache';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { driveErrorMessage } from './errors';
import { extractFolderId } from './model';

/**
 * Drive connection actions. They shape input and call the database API with the user's session;
 * `integration.manage` and every rule are enforced by the database (tests/acceptance/increment-8).
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
const scopeSchema = z.object({ workspaceSlug: z.string().refine(isSlug), clientId: z.uuid() });

async function call(
  fn: string,
  args: Record<string, unknown>,
  scope: z.infer<typeof scopeSchema>,
): Promise<ActionState | null> {
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return { status: 'error', message: 'A autenticação não está configurada neste ambiente.' };
  }
  const { error } = await supabase.rpc(fn, args);
  if (error !== null) {
    if (!['42501', 'P0002', '22023'].includes(error.code)) {
      console.error(`drive action failed: ${fn} (${error.code})`);
    }
    return {
      status: 'error',
      message: driveErrorMessage({ code: error.code, message: error.message }),
    };
  }
  revalidatePath(`/w/${scope.workspaceSlug}/clients/${scope.clientId}/drive`);
  revalidatePath(`/w/${scope.workspaceSlug}/automations`);
  return null;
}

export async function connectDriveFolder(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = scopeSchema
    .extend({
      folder: z.string().trim().min(1).max(500),
      credentialRef: z.string().trim().max(40).optional(),
      interval: z.coerce.number().int().optional(),
    })
    .safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Informe a pasta do Drive.' };
  const f = parsed.data;
  const failure = await call(
    'connect_drive_folder',
    {
      p_client_id: f.clientId,
      p_root_folder_id: extractFolderId(f.folder),
      p_credential_ref:
        f.credentialRef === undefined || f.credentialRef === '' ? 'default' : f.credentialRef,
      p_sync_interval_minutes: f.interval ?? 60,
    },
    f,
  );
  return (
    failure ?? {
      status: 'success',
      message: 'Pasta conectada. A primeira sincronização está na fila.',
    }
  );
}

export async function requestDriveSync(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = scopeSchema.extend({ connectionId: z.uuid() }).safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call('request_drive_sync', { p_connection_id: f.connectionId }, f);
  return failure ?? { status: 'success', message: 'Sincronização solicitada.' };
}

export async function setDriveConnectionStatus(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = scopeSchema
    .extend({ connectionId: z.uuid(), decision: z.enum(['active', 'paused']) })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call(
    'set_drive_connection_status',
    { p_connection_id: f.connectionId, p_status: f.decision },
    f,
  );
  return (
    failure ?? {
      status: 'success',
      message: f.decision === 'paused' ? 'Conexão pausada.' : 'Conexão retomada.',
    }
  );
}

export async function requestFileReindex(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = scopeSchema.extend({ fileId: z.uuid() }).safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const failure = await call('request_file_reindex', { p_file_id: f.fileId }, f);
  return failure ?? { status: 'success', message: 'Arquivo marcado para indexar de novo.' };
}
