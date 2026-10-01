import type { ReactNode } from 'react';
import { AppShell } from '@jmos/ui';
import { PortalNavigation } from '@/components/portal-navigation';
import { SignOutButton } from '@/components/sign-out-button';
import { requireSessionUser } from '@/lib/auth/session';

/**
 * Client Portal surface: mobile-first shell (docs/00 §3.2, docs/06).
 * Must never render internal navigation, notes, AI traces or job details (docs/07 §14).
 */
export default async function PortalLayout({ children }: { children: ReactNode }) {
  await requireSessionUser('/portal');
  return (
    <AppShell
      variant="portal"
      header={
        <div className="flex items-center justify-between gap-3">
          <p className="text-sm font-semibold">Portal do Cliente · Jansen</p>
          <SignOutButton compact />
        </div>
      }
      navigation={<PortalNavigation />}
    >
      {children}
    </AppShell>
  );
}
