import type { ReactNode } from 'react';

export interface EmptyStateProps {
  title: string;
  description?: string;
  icon?: ReactNode;
  action?: ReactNode;
  /** Heading level of the title, so it fits the surrounding outline (default h2). */
  headingLevel?: 2 | 3;
}

export function EmptyState({
  title,
  description,
  icon,
  action,
  headingLevel = 2,
}: EmptyStateProps) {
  const Heading = headingLevel === 3 ? 'h3' : 'h2';
  return (
    <div className="flex flex-col items-center justify-center rounded-lg border border-dashed bg-surface px-6 py-12 text-center">
      {icon ? <div className="mb-3 text-muted-foreground">{icon}</div> : null}
      <Heading className="text-sm font-medium">{title}</Heading>
      {description ? (
        <p className="mt-1 max-w-md text-sm text-muted-foreground">{description}</p>
      ) : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}
