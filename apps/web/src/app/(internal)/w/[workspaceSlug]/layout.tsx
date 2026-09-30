import type { ReactNode } from 'react';
import { notFound } from 'next/navigation';
import { AppShell } from '@jmos/ui';
import { InternalNavigation } from '@/components/internal-navigation';
import { requireSessionUser } from '@/lib/auth/session';
import { getWorkspaceBySlug, listMyWorkspaces } from '@/lib/identity/queries';

/**
 * Jansen Internal OS surface (docs/00 §3.1). The workspace is resolved through row level security:
 * a slug the user is not an active member of is indistinguishable from one that does not exist.
 */
export default async function WorkspaceLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ workspaceSlug: string }>;
}) {
  const { workspaceSlug } = await params;
  const user = await requireSessionUser(`/w/${workspaceSlug}`);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  const workspaces = await listMyWorkspaces();

  return (
    <AppShell
      variant="internal"
      navigation={
        <InternalNavigation workspace={workspace} workspaces={workspaces} userEmail={user.email} />
      }
    >
      {children}
    </AppShell>
  );
}
