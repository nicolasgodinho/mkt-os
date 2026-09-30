'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@jmos/ui';
import { portalNavigation } from '@/navigation';

export function PortalNavigation() {
  const pathname = usePathname();
  const items = portalNavigation.filter((item) => item.available);

  return (
    <nav aria-label="Navegação do portal" className="mx-auto w-full max-w-3xl px-2 md:px-4">
      <ul className="flex gap-1 overflow-x-auto py-1.5">
        {items.map(({ href, label, icon: Icon }) => {
          const active = pathname === href;
          return (
            <li key={href} className="min-w-16 flex-1 md:flex-none">
              <Link
                href={href}
                aria-current={active ? 'page' : undefined}
                className={cn(
                  'flex flex-col items-center gap-0.5 rounded-md px-3 py-1.5 text-xs text-muted-foreground md:flex-row md:gap-2 md:text-sm',
                  active && 'font-medium text-foreground',
                )}
              >
                <Icon aria-hidden className="size-5 md:size-4" />
                {label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
