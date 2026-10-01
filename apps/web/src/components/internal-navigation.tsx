'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Sidebar, SidebarItem } from '@jmos/ui';
import type { Workspace } from '@/lib/identity/queries';
import { internalNavigation } from '@/navigation';
import { SignOutButton } from './sign-out-button';

interface InternalNavigationProps {
  workspace: Workspace;
  workspaces: readonly Workspace[];
  userEmail: string | null;
}

export function InternalNavigation({ workspace, workspaces, userEmail }: InternalNavigationProps) {
  const pathname = usePathname();
  const home = `/w/${workspace.slug}`;

  return (
    <Sidebar
      label="Navegação principal"
      header={
        <div>
          <p className="text-sm font-semibold">Jansen Marketing OS</p>
          <p className="text-xs text-muted-foreground" data-testid="current-workspace">
            {workspace.name}
          </p>
          {workspaces.length > 1 ? (
            <nav aria-label="Trocar de workspace" className="mt-2 flex flex-col gap-0.5">
              {workspaces
                .filter((other) => other.id !== workspace.id)
                .map((other) => (
                  <Link
                    key={other.id}
                    href={`/w/${other.slug}`}
                    className="text-xs text-muted-foreground hover:text-foreground"
                  >
                    Ir para {other.name}
                  </Link>
                ))}
            </nav>
          ) : null}
        </div>
      }
      footer={
        <div className="flex flex-col gap-2">
          {userEmail ? (
            <p className="truncate text-xs text-muted-foreground" title={userEmail}>
              {userEmail}
            </p>
          ) : null}
          <SignOutButton compact />
        </div>
      }
    >
      {internalNavigation(workspace.slug).map(({ href, label, icon: Icon, available }) => (
        <SidebarItem
          key={href}
          href={href}
          label={label}
          icon={<Icon aria-hidden className="size-4 shrink-0" />}
          active={available && (href === home ? pathname === home : pathname.startsWith(href))}
          unavailableHint={available ? undefined : 'em breve'}
          linkComponent={Link}
        />
      ))}
    </Sidebar>
  );
}
