'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { CAPABILITIES } from '@/lib/identity/capabilities';
import { isSlug } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { adminErrorMessage } from './errors';
import { CLIENT_ROLES, invitationUrl, TOKEN, WORKSPACE_ROLES } from './model';
import { publicOrigin } from './queries';

/**
 * Administration actions: they shape input and call the capability-checked database API with the
 * user's session (Increment 1 identity API, Increment 9 invitations). The web app never holds a
 * service-role key (ADR 0005).
 */

const INVALID: ActionState = { status: 'error', message: 'Dados inválidos.' };

/** Form values; repeated fields (capability checkboxes) are collected as arrays. */
function values(formData: FormData): Record<string, string | string[]> {
  const result: Record<string, string | string[]> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value !== 'string') continue;
    const current = result[key];
    if (key === 'capabilities') {
      result[key] = [...(Array.isArray(current) ? current : []), value];
    } else {
      result[key] = value;
    }
  }
  return result;
}

const workspaceScope = z.object({
  workspaceSlug: z.string().refine(isSlug),
  workspaceId: z.uuid(),
});
const clientScope = workspaceScope.extend({ clientId: z.uuid() });
const capabilities = z.array(z.enum(CAPABILITIES)).default([]);

async function rpc(
  fn: string,
  args: Record<string, unknown>,
  paths: string[],
): Promise<{ failure: ActionState | null; data: unknown }> {
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return {
      failure: { status: 'error', message: 'A autenticação não está configurada neste ambiente.' },
      data: null,
    };
  }
  const result = await supabase.rpc(fn, args);
  const error = result.error;
  // Untyped RPC result: every caller parses it with zod.
  const data: unknown = result.data;
  if (error !== null) {
    if (!['42501', 'P0002', '22023', '23505'].includes(error.code)) {
      console.error(`administration action failed: ${fn} (${error.code})`);
    }
    return {
      failure: {
        status: 'error',
        message: adminErrorMessage({ code: error.code, message: error.message }),
      },
      data: null,
    };
  }
  for (const path of paths) revalidatePath(path);
  return { failure: null, data };
}

const settingsPaths = (slug: string) => [`/w/${slug}/settings`, `/w/${slug}/settings/clients`];
const clientAccessPath = (slug: string, clientId: string) =>
  `/w/${slug}/clients/${clientId}/access`;

async function invitationMessage(data: unknown): Promise<ActionState> {
  const row = z.array(z.object({ token: z.string().regex(TOKEN) })).parse(data)[0];
  if (row === undefined) return INVALID;
  return {
    status: 'success',
    message: `Convite criado. Envie este link para a pessoa (vale por 7 dias e só aparece agora): ${invitationUrl(await publicOrigin(), row.token)}`,
  };
}

// ---------------------------------------------------------------------------
// Internal team
// ---------------------------------------------------------------------------
export async function inviteWorkspaceMember(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = workspaceScope
    .extend({ email: z.string().trim().max(320), role: z.enum(WORKSPACE_ROLES), capabilities })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure, data } = await rpc(
    'invite_workspace_member',
    {
      p_workspace_id: f.workspaceId,
      p_email: f.email,
      p_role: f.role,
      p_capabilities: f.capabilities,
    },
    settingsPaths(f.workspaceSlug),
  );
  return failure ?? invitationMessage(data);
}

export async function setWorkspaceMember(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = workspaceScope
    .extend({ userId: z.uuid(), role: z.enum(WORKSPACE_ROLES), capabilities })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure } = await rpc(
    'set_workspace_member',
    {
      p_workspace_id: f.workspaceId,
      p_user_id: f.userId,
      p_role: f.role,
      p_capabilities: f.capabilities,
    },
    settingsPaths(f.workspaceSlug),
  );
  return failure ?? { status: 'success', message: 'Acesso atualizado.' };
}

export async function revokeWorkspaceMember(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = workspaceScope.extend({ userId: z.uuid() }).safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure } = await rpc(
    'revoke_workspace_member',
    { p_workspace_id: f.workspaceId, p_user_id: f.userId },
    settingsPaths(f.workspaceSlug),
  );
  return failure ?? { status: 'success', message: 'Acesso revogado.' };
}

export async function revokeInvitation(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = workspaceScope
    .extend({ invitationId: z.uuid(), clientId: z.uuid().optional() })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure } = await rpc(
    'revoke_invitation',
    { p_invitation_id: f.invitationId },
    f.clientId === undefined
      ? settingsPaths(f.workspaceSlug)
      : [clientAccessPath(f.workspaceSlug, f.clientId)],
  );
  return failure ?? { status: 'success', message: 'Convite revogado.' };
}

// ---------------------------------------------------------------------------
// Clients
// ---------------------------------------------------------------------------
export async function createClient(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = workspaceScope
    .extend({ name: z.string().trim().min(1).max(200), slug: z.string().trim().max(60) })
    .safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Informe o nome do cliente.' };
  const f = parsed.data;
  const { failure } = await rpc(
    'create_client',
    { p_workspace_id: f.workspaceId, p_name: f.name, p_slug: f.slug },
    [...settingsPaths(f.workspaceSlug), `/w/${f.workspaceSlug}/clients`],
  );
  return failure ?? { status: 'success', message: 'Cliente criado.' };
}

export async function renameClient(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = clientScope
    .extend({ name: z.string().trim().min(1).max(200) })
    .safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Informe o nome do cliente.' };
  const f = parsed.data;
  const { failure } = await rpc('update_client', { p_client_id: f.clientId, p_name: f.name }, [
    ...settingsPaths(f.workspaceSlug),
    `/w/${f.workspaceSlug}/clients`,
  ]);
  return failure ?? { status: 'success', message: 'Nome atualizado.' };
}

export async function archiveClient(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = clientScope.safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure } = await rpc('archive_client', { p_client_id: f.clientId }, [
    ...settingsPaths(f.workspaceSlug),
    `/w/${f.workspaceSlug}/clients`,
  ]);
  return failure ?? { status: 'success', message: 'Cliente arquivado.' };
}

// ---------------------------------------------------------------------------
// Client access (portal members)
// ---------------------------------------------------------------------------
export async function inviteClientMember(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = clientScope
    .extend({ email: z.string().trim().max(320), role: z.enum(CLIENT_ROLES), capabilities })
    .safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure, data } = await rpc(
    'invite_client_member',
    { p_client_id: f.clientId, p_email: f.email, p_role: f.role, p_capabilities: f.capabilities },
    [clientAccessPath(f.workspaceSlug, f.clientId)],
  );
  return failure ?? invitationMessage(data);
}

export async function revokeClientMember(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = clientScope.extend({ userId: z.uuid() }).safeParse(values(formData));
  if (!parsed.success) return INVALID;
  const f = parsed.data;
  const { failure } = await rpc(
    'revoke_client_member',
    { p_client_id: f.clientId, p_user_id: f.userId },
    [clientAccessPath(f.workspaceSlug, f.clientId)],
  );
  return failure ?? { status: 'success', message: 'Acesso revogado.' };
}

// ---------------------------------------------------------------------------
// Accepting an invitation (/convite/<token>)
// ---------------------------------------------------------------------------
async function destination(workspaceId: string, clientId: string | null): Promise<string> {
  if (clientId !== null) return `/portal/${clientId}`;
  const supabase = await createSupabaseWriter();
  const { data } =
    supabase === null
      ? { data: null }
      : await supabase.from('workspaces').select('slug').eq('id', workspaceId).maybeSingle();
  const slug = z.object({ slug: z.string() }).safeParse(data);
  return slug.success ? `/w/${slug.data.slug}` : '/';
}

async function accept(token: string): Promise<ActionState> {
  const { failure, data } = await rpc('accept_invitation', { p_token: token }, []);
  if (failure !== null) return failure;
  const row = z
    .array(z.object({ workspace_id: z.uuid(), client_id: z.uuid().nullable() }))
    .parse(data)[0];
  if (row === undefined) return INVALID;
  redirect(await destination(row.workspace_id, row.client_id));
}

export async function acceptInvitation(_p: ActionState, formData: FormData): Promise<ActionState> {
  const parsed = z.object({ token: z.string().regex(TOKEN) }).safeParse(values(formData));
  if (!parsed.success) return { status: 'error', message: 'Link de convite inválido.' };
  return accept(parsed.data.token);
}

const signUpSchema = z.object({
  token: z.string().regex(TOKEN),
  name: z.string().trim().min(1).max(200),
  email: z.email().max(320),
  password: z.string().min(10).max(200),
});

export async function signUpWithInvitation(
  _p: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const parsed = signUpSchema.safeParse(values(formData));
  if (!parsed.success) {
    return {
      status: 'error',
      message: 'Informe nome, o e-mail convidado e uma senha com pelo menos 10 caracteres.',
    };
  }
  const f = parsed.data;
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return { status: 'error', message: 'A autenticação não está configurada neste ambiente.' };
  }
  const origin = await publicOrigin();
  const { data, error } = await supabase.auth.signUp({
    email: f.email,
    password: f.password,
    options: {
      data: { display_name: f.name },
      // After confirming the e-mail, the person comes back to the invitation to accept it.
      emailRedirectTo: `${origin}/convite/${f.token}`,
    },
  });
  if (error !== null) {
    // The signup hook refuses e-mails without an invitation; never reveal which case applied.
    return {
      status: 'error',
      message:
        'Não foi possível criar a conta com este e-mail. Use exatamente o e-mail que recebeu o convite; se você já tem conta, entre e abra o link de novo.',
    };
  }
  if (data.session === null) {
    return {
      status: 'success',
      message: 'Conta criada. Confirme seu e-mail pelo link que enviamos e volte a este convite.',
    };
  }
  return accept(f.token);
}
