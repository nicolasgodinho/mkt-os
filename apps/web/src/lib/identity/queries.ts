import 'server-only';
import { cache } from 'react';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import { capabilityListSchema, type Capability } from './capabilities';
import { isSlug, isUuid } from './routing';

/**
 * Identity reads for the shells. Every query runs with the signed-in user's session, so Postgres
 * row level security decides what is returned. Filters here only narrow results; they never grant
 * access. Unexpected errors are thrown (and logged by Next.js) rather than hidden.
 */

const workspaceSchema = z.object({ id: z.uuid(), name: z.string(), slug: z.string() });
const clientSchema = z.object({
  id: z.uuid(),
  workspace_id: z.uuid(),
  name: z.string(),
  slug: z.string(),
  status: z.enum(['active', 'archived']),
});
const portalMembershipSchema = z.object({
  client_id: z.uuid(),
  role: z.enum(['client_admin', 'approver', 'collaborator', 'viewer']),
});

export type Workspace = z.infer<typeof workspaceSchema>;
export type Client = z.infer<typeof clientSchema>;
export type PortalMembership = z.infer<typeof portalMembershipSchema>;

class DataAccessError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`identity data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'DataAccessError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new DataAccessError('client unavailable', 'not_configured');
  return supabase;
}

export const listMyWorkspaces = cache(async (): Promise<Workspace[]> => {
  const supabase = await reader();
  const { data, error } = await supabase.from('workspaces').select('id, name, slug').order('name');
  if (error !== null) throw new DataAccessError('list workspaces', error.code);
  return z.array(workspaceSchema).parse(data);
});

export const getWorkspaceBySlug = cache(async (slug: string): Promise<Workspace | null> => {
  if (!isSlug(slug)) return null;
  const supabase = await reader();
  const { data, error } = await supabase
    .from('workspaces')
    .select('id, name, slug')
    .eq('slug', slug)
    .maybeSingle();
  if (error !== null) throw new DataAccessError('get workspace', error.code);
  return data === null ? null : workspaceSchema.parse(data);
});

export const listWorkspaceClients = cache(async (workspaceId: string): Promise<Client[]> => {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('clients')
    .select('id, workspace_id, name, slug, status')
    .eq('workspace_id', workspaceId)
    .order('name');
  if (error !== null) throw new DataAccessError('list clients', error.code);
  return z.array(clientSchema).parse(data);
});

export const getClient = cache(async (clientId: string): Promise<Client | null> => {
  if (!isUuid(clientId)) return null;
  const supabase = await reader();
  const { data, error } = await supabase
    .from('clients')
    .select('id, workspace_id, name, slug, status')
    .eq('id', clientId)
    .maybeSingle();
  if (error !== null) throw new DataAccessError('get client', error.code);
  return data === null ? null : clientSchema.parse(data);
});

/** Active client-side memberships of the signed-in user (portal access). */
export const listMyPortalMemberships = cache(
  async (userId: string): Promise<PortalMembership[]> => {
    const supabase = await reader();
    const { data, error } = await supabase
      .from('client_memberships')
      .select('client_id, role')
      .eq('user_id', userId)
      .eq('status', 'active');
    if (error !== null) throw new DataAccessError('list portal memberships', error.code);
    return z.array(portalMembershipSchema).parse(data);
  },
);

export const getWorkspaceCapabilities = cache(
  async (workspaceId: string): Promise<Capability[]> => {
    const supabase = await reader();
    const result = await supabase.rpc('workspace_capabilities', { p_workspace_id: workspaceId });
    if (result.error !== null) {
      throw new DataAccessError('workspace capabilities', result.error.code);
    }
    // Untyped RPC results are only trusted after validation against the capability contract.
    return capabilityListSchema.parse(result.data);
  },
);

export const getClientCapabilities = cache(async (clientId: string): Promise<Capability[]> => {
  const supabase = await reader();
  const result = await supabase.rpc('client_capabilities', { p_client_id: clientId });
  if (result.error !== null) throw new DataAccessError('client capabilities', result.error.code);
  return capabilityListSchema.parse(result.data);
});
