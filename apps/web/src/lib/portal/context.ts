import 'server-only';
import { notFound } from 'next/navigation';
import { requireSessionUser, type SessionUser } from '@/lib/auth/session';
import type { Capability } from '@/lib/identity/capabilities';
import { isUuid } from '@/lib/identity/routing';
import {
  getClient,
  getClientCapabilities,
  listMyPortalMemberships,
  type Client,
  type PortalMembership,
} from '@/lib/identity/queries';

export interface PortalContext {
  user: SessionUser;
  client: Client;
  membership: PortalMembership;
  capabilities: Capability[];
}

/**
 * Portal pages require an active client-side membership for exactly this client; anything else
 * renders the shared 404 (docs/05 §1). The database enforces every read and decision anyway.
 */
export async function requirePortalContext(
  clientId: string,
  returnTo: string,
): Promise<PortalContext> {
  if (!isUuid(clientId)) notFound();
  const user = await requireSessionUser(returnTo);
  const membership = (await listMyPortalMemberships(user.id)).find((m) => m.client_id === clientId);
  if (membership === undefined) notFound();
  const client = await getClient(clientId);
  if (client === null) notFound();
  return { user, client, membership, capabilities: await getClientCapabilities(clientId) };
}
