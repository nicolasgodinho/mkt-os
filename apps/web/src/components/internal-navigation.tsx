'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Sidebar, SidebarItem } from '@jmos/ui';
import { internalNavigation } from '@/navigation';

export function InternalNavigation() {
  const pathname = usePathname();

  return (
    <Sidebar
      label="Navegação principal"
      header={
        <div>
          <p className="text-sm font-semibold">Jansen Marketing OS</p>
          <p className="text-xs text-muted-foreground">Interno</p>
        </div>
      }
    >
      {internalNavigation.map(({ href, label, icon: Icon, available }) => (
        <SidebarItem
          key={href}
          href={href}
          label={label}
          icon={<Icon aria-hidden className="size-4 shrink-0" />}
          active={available && pathname === href}
          unavailableHint={available ? undefined : 'em breve'}
          linkComponent={Link}
        />
      ))}
    </Sidebar>
  );
}
