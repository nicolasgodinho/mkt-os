import 'server-only';
import { getWorkspaceCapabilities } from '@/lib/identity/queries';

/**
 * Which content controls to show. Internal capabilities are workspace-wide (Increment 1 D1);
 * the database enforces every action regardless of what is shown.
 */
export async function capabilityFlags(workspaceId: string) {
  const capabilities = await getWorkspaceCapabilities(workspaceId);
  return {
    strategy: capabilities.includes('strategy.edit'),
    create: capabilities.includes('content.create'),
    edit: capabilities.includes('content.edit'),
    review: capabilities.includes('content.review_internal'),
  };
}
