import type { ReactNode } from 'react';

export interface AppShellProps {
  /**
   * `internal`: desktop-first, dense layout with a persistent sidebar (docs/00 §3.1).
   * `portal`: mobile-first layout with a header and bottom navigation (docs/00 §3.2).
   */
  variant: 'internal' | 'portal';
  navigation: ReactNode;
  /**
   * Internal only: compact bar shown below the `md` breakpoint, where the sidebar is hidden.
   * Desktop-first still has to leave a small screen with navigation and sign-out.
   */
  compactNavigation?: ReactNode;
  header?: ReactNode;
  children: ReactNode;
}

export function AppShell({
  variant,
  navigation,
  compactNavigation,
  header,
  children,
}: AppShellProps) {
  if (variant === 'internal') {
    return (
      <div className="flex min-h-dvh" data-shell="internal">
        <aside className="hidden w-60 shrink-0 border-r bg-surface md:flex md:flex-col">
          {navigation}
        </aside>
        <div className="flex min-w-0 flex-1 flex-col">
          {compactNavigation ? (
            <div className="border-b bg-surface px-4 py-2 md:hidden">{compactNavigation}</div>
          ) : null}
          {header}
          <main id="main" className="flex-1 px-6 py-6">
            {children}
          </main>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-dvh flex-col" data-shell="portal">
      {header ? (
        <header className="sticky top-0 z-10 border-b bg-surface/95 px-4 py-3 backdrop-blur">
          {header}
        </header>
      ) : null}
      <main id="main" className="mx-auto w-full max-w-3xl flex-1 px-4 pt-4 pb-24 md:pb-8">
        {children}
      </main>
      <div className="fixed inset-x-0 bottom-0 z-10 border-t bg-surface md:static md:border-t-0 md:bg-transparent">
        {navigation}
      </div>
    </div>
  );
}
