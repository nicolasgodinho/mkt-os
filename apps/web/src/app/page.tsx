import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { requireSessionUser } from '@/lib/auth/session';
import { listMyPortalMemberships, listMyWorkspaces } from '@/lib/identity/queries';
import { NoAccess } from '@/components/no-access';

export const metadata: Metadata = { title: 'Início' };

/** Entry point: internal members go to their workspace, client-side members to the portal. */
export default async function EntryPage() {
  const user = await requireSessionUser('/');
  const [workspace] = await listMyWorkspaces();
  if (workspace !== undefined) redirect(`/w/${workspace.slug}`);
  const memberships = await listMyPortalMemberships(user.id);
  if (memberships.length > 0) redirect('/portal');
  return <NoAccess email={user.email} />;
}
