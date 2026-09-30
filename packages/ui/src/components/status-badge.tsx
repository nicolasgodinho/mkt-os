import type { ReactNode } from 'react';
import { cn } from '../cn';

export type StatusTone = 'neutral' | 'info' | 'success' | 'warning' | 'danger';

const toneClasses: Record<StatusTone, string> = {
  neutral: 'bg-status-neutral-surface text-status-neutral',
  info: 'bg-status-info-surface text-status-info',
  success: 'bg-status-success-surface text-status-success',
  warning: 'bg-status-warning-surface text-status-warning',
  danger: 'bg-status-danger-surface text-status-danger',
};

export interface StatusBadgeProps {
  tone: StatusTone;
  children: ReactNode;
}

/** Compact status label. Always pair the tone with text; never convey status by color alone. */
export function StatusBadge({ tone, children }: StatusBadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center rounded-sm px-1.5 py-0.5 text-[11px] leading-none font-medium',
        toneClasses[tone],
      )}
    >
      {children}
    </span>
  );
}
