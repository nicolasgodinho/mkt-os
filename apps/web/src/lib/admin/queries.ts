import 'server-only';
import { headers } from 'next/headers';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  clientMemberSchema,
  invitationSchema,
  workspaceMemberSchema,
  type ClientMember,
  type Invitation,
  type WorkspaceMember,
} from './model';

/** Administration reads with the user's session; the database decides what managers may see. */

class AdminDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`administration data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'AdminDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new AdminDataError('client unavailable', 'not_configured');
  return supabase;
}

export async function workspaceMembers(workspaceId: string): Promise<WorkspaceMember[]> {
  const supabase = await reader();
  const result = await supabase.rpc('workspace_members', { p_workspace_id: workspaceId });
  if (result.error !== null) throw new AdminDataError('workspace members', result.error.code);
  return z.array(workspaceMemberSchema).parse(result.data);
}

export async function clientMembers(clientId: string): Promise<ClientMember[]> {
  const supabase = await reader();
  const result = await supabase.rpc('client_members', { p_client_id: clientId });
  if (result.error !== null) throw new AdminDataError('client members', result.error.code);
  return z.array(clientMemberSchema).parse(result.data);
}

const INVITATION_COLUMNS =
  'id, client_id, email, workspace_role, client_role, capabilities, status, expires_at, created_at';

/** Internal invitations of a workspace, or the invitations of one client. */
export async function listInvitations(
  target: { workspaceId: string } | { clientId: string },
): Promise<Invitation[]> {
  const supabase = await reader();
  let query = supabase.from('invitations').select(INVITATION_COLUMNS);
  query =
    'clientId' in target
      ? query.eq('client_id', target.clientId)
      : query.eq('workspace_id', target.workspaceId).is('client_id', null);
  const { data, error } = await query.order('created_at', { ascending: false }).limit(100);
  if (error !== null) throw new AdminDataError('invitations', error.code);
  return z.array(invitationSchema).parse(data);
}

/**
 * The public origin used in invitation links: `JMOS_PUBLIC_URL` when the deployment sets it
 * (recommended), else the request's own host.
 */
export async function publicOrigin(): Promise<string> {
  const configured = process.env.JMOS_PUBLIC_URL;
  if (configured !== undefined && /^https?:\/\/[^\s/]+/.test(configured)) return configured;
  const request = await headers();
  const host = request.get('x-forwarded-host') ?? request.get('host') ?? 'localhost';
  const proto = request.get('x-forwarded-proto') ?? 'http';
  return `${proto.split(',')[0] ?? 'http'}://${host}`;
}
