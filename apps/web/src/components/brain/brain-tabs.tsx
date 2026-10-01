'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@jmos/ui';

/** Client Brain sections (docs/07 §4 and §12). */
export function BrainTabs({ basePath }: { basePath: string }) {
  const pathname = usePathname();
  const tabs = [
    { href: basePath, label: 'Visão geral' },
    { href: `${basePath}/knowledge`, label: 'Conhecimento' },
    { href: `${basePath}/rules`, label: 'Regras' },
  ];

  return (
    <nav aria-label="Seções do Client Brain" className="mb-6 border-b">
      <ul className="-mb-px flex gap-1 overflow-x-auto">
        {tabs.map((tab) => {
          const active = pathname === tab.href;
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
