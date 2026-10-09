import 'server-only';
import { notFound } from 'next/navigation';
import { requireSessionUser, type SessionUser } from '@/lib/auth/session';
import type { Capability } from '@/lib/identity/capabilities';
import { isUuid } from '@/lib/identity/routing';
import {
  getClient,
  getClientCapabilities,
  getWorkspaceBySlug,
  getWorkspaceCapabilities,
  type Client,
  type Workspace,
} from '@/lib/identity/queries';

/**
 * Administration pages render only for members holding the capability they manage; everyone else
 * gets the shared 404 (docs/05 §1). The database checks every action again.
 */
export async function requireWorkspaceAdmin(
  workspaceSlug: string,
  capability: Capability,
  returnTo: string,
): Promise<{ user: SessionUser; workspace: Workspace; capabilities: Capability[] }> {
  const user = await requireSessionUser(returnTo);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  const capabilities = await getWorkspaceCapabilities(workspace.id);
  if (!capabilities.includes(capability)) notFound();
  return { user, workspace, capabilities };
}

export async function requireClientAdmin(
  workspaceSlug: string,
  clientId: string,
  returnTo: string,
): Promise<{ user: SessionUser; workspace: Workspace; client: Client }> {
  const user = await requireSessionUser(returnTo);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null || !isUuid(clientId)) notFound();
  const client = await getClient(clientId);
  if (client?.workspace_id !== workspace.id) notFound();
  if (!(await getClientCapabilities(clientId)).includes('client.manage')) notFound();
  return { user, workspace, client };
}
