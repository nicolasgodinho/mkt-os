import type { ElementType, ReactNode } from 'react';
import { cn } from '../cn';
import { StatusBadge } from './status-badge';

export interface SidebarProps {
  label: string;
  header?: ReactNode;
  footer?: ReactNode;
  children: ReactNode;
}

export function Sidebar({ label, header, footer, children }: SidebarProps) {
  return (
    <div className="flex h-full flex-col">
      {header ? <div className="border-b px-4 py-3">{header}</div> : null}
      <nav aria-label={label} className="flex-1 overflow-y-auto px-2 py-3">
        <ul className="flex flex-col gap-0.5">{children}</ul>
      </nav>
      {footer ? <div className="border-t px-4 py-3">{footer}</div> : null}
    </div>
  );
}

export interface SidebarItemProps {
  href: string;
  label: string;
  icon?: ReactNode;
  active?: boolean;
  /** Module not built yet: rendered as non-interactive text so nothing links to a fake page. */
  unavailableHint?: string;
  /** Framework link component (e.g. next/link). Defaults to a plain anchor. */
  linkComponent?: ElementType;
}

export function SidebarItem({
  href,
  label,
  icon,
  active = false,
  unavailableHint,
  linkComponent: Link = 'a',
}: SidebarItemProps) {
  const base = 'flex h-8 items-center gap-2 rounded-md px-2 text-sm';

  if (unavailableHint !== undefined) {
    return (
      <li>
        <span aria-disabled="true" className={cn(base, 'cursor-default text-muted-foreground')}>
          {icon}
          <span className="flex-1 truncate" title={label}>
            {label}
          </span>
          <StatusBadge tone="neutral">{unavailableHint}</StatusBadge>
        </span>
      </li>
    );
  }

  return (
    <li>
      <Link
        href={href}
        aria-current={active ? 'page' : undefined}
        className={cn(
          base,
          'transition-colors hover:bg-surface-muted',
          active && 'bg-surface-muted font-medium text-foreground',
        )}
      >
        {icon}
        <span className="flex-1 truncate">{label}</span>
      </Link>
    </li>
  );
}
