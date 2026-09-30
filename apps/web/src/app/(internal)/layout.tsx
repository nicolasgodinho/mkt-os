import type { ReactNode } from 'react';
import { AppShell } from '@jmos/ui';
import { InternalNavigation } from '@/components/internal-navigation';

/** Jansen Internal OS surface: desktop-first shell (docs/00 §3.1, docs/06). */
export default function InternalLayout({ children }: { children: ReactNode }) {
  return (
    <AppShell variant="internal" navigation={<InternalNavigation />}>
      {children}
    </AppShell>
  );
}
