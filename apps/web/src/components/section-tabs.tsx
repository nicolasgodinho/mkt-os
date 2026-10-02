'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@jmos/ui';

export interface SectionTab {
  href: string;
  label: string;
  /** Also active on nested pages (e.g. a pauta under the pautas tab). */
  prefixes?: readonly string[];
}

/** Sub-navigation for a section; the active tab gets aria-current="page". */
export function SectionTabs({ label, tabs }: { label: string; tabs: readonly SectionTab[] }) {
  const pathname = usePathname();
  return (
    <nav aria-label={label} className="mb-6 border-b">
      <ul className="-mb-px flex gap-1 overflow-x-auto">
        {tabs.map((tab) => {
          const active =
            pathname === tab.href ||
            (tab.prefixes ?? []).some((prefix) => pathname.startsWith(prefix));
          return (
            <li key={tab.href}>
              <Link
                href={tab.href}
                aria-current={active ? 'page' : undefined}
                className={cn(
                  'inline-flex h-9 items-center border-b-2 px-3 text-sm whitespace-nowrap',
                  active
                    ? 'border-primary font-medium text-foreground'
                    : 'border-transparent text-muted-foreground hover:text-foreground',
                )}
              >
                {tab.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
