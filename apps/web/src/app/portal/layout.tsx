import type { ReactNode } from 'react';
import { AppShell } from '@jmos/ui';
import { PortalNavigation } from '@/components/portal-navigation';

/**
 * Client Portal surface: mobile-first shell (docs/00 §3.2, docs/06).
 * Must never render internal navigation, notes, AI traces or job details.
 */
export default function PortalLayout({ children }: { children: ReactNode }) {
  return (
    <AppShell
      variant="portal"
      header={<p className="text-sm font-semibold">Portal do Cliente · Jansen</p>}
      navigation={<PortalNavigation />}
    >
      {children}
    </AppShell>
  );
}
