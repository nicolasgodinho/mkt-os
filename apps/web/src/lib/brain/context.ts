import 'server-only';
import { notFound } from 'next/navigation';
import { cache } from 'react';
import { requireSessionUser } from '@/lib/auth/session';
import type { Capability } from '@/lib/identity/capabilities';
import {
  getClient,
  getClientCapabilities,
  getWorkspaceBySlug,
  type Client,
  type Workspace,
} from '@/lib/identity/queries';

export interface BrainContext {
  workspace: Workspace;
  client: Client;
  /** Where the Brain lives, e.g. /w/jansen/clients/<id>/brain. */
  basePath: string;
  can: {
    editStrategy: boolean;
    propose: boolean;
    approveKnowledge: boolean;
    activateRules: boolean;
  };
}

function has(capabilities: readonly Capability[], capability: Capability): boolean {
  return capabilities.includes(capability);
}

/**
 * Resolves the workspace and client of a Client Brain route, or renders the shared 404. The
 * capability flags only decide which controls are shown; the database enforces every action.
 * Layouts and pages render in parallel, so each of them calls this (and the session check).
 */
export const resolveBrainContext = cache(
  async (workspaceSlug: string, clientId: string, returnTo: string): Promise<BrainContext> => {
    await requireSessionUser(returnTo);
    const workspace = await getWorkspaceBySlug(workspaceSlug);
    if (workspace === null) notFound();
    const client = await getClient(clientId);
    if (client?.workspace_id !== workspace.id) notFound();
    const capabilities = await getClientCapabilities(client.id);
    // The Client Brain is internal-only (TEST_SPEC decision 3).
    if (!has(capabilities, 'client.view')) notFound();

    return {
      workspace,
      client,
      basePath: `/w/${workspace.slug}/clients/${client.id}/brain`,
      can: {
        editStrategy: has(capabilities, 'strategy.edit'),
        propose: has(capabilities, 'knowledge.propose'),
        approveKnowledge: has(capabilities, 'knowledge.approve'),
        activateRules: has(capabilities, 'rule.activate'),
      },
    };
  },
);
