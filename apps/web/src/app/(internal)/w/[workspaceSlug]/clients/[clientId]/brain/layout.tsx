import type { ReactNode } from 'react';
import Link from 'next/link';
import { PageHeader } from '@jmos/ui';
import { BrainTabs } from '@/components/brain/brain-tabs';
import { resolveBrainContext } from '@/lib/brain/context';
import { listRuleConflicts } from '@/lib/brain/queries';

/**
 * Client Brain (docs/07 §4): internal-only context, knowledge and rules of one client. Rule
 * conflicts are shown on every Brain page (docs/07 §12: conflicts are prominent).
 */
export default async function BrainLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const context = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/brain`,
  );
  const conflicts = await listRuleConflicts(context.client.id);
  const conflictingSubjects = [
    ...new Set(conflicts.map((rule) => rule.subject).filter((subject) => subject !== null)),
  ];

  return (
    <>
      <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
        <Link href={`/w/${context.workspace.slug}/clients`} className="hover:text-foreground">
          Clientes
        </Link>
        <span aria-hidden> / </span>
        <Link
          href={`/w/${context.workspace.slug}/clients/${context.client.id}`}
          className="hover:text-foreground"
        >
          {context.client.name}
        </Link>
      </nav>
      <PageHeader
        title={`Client Brain: ${context.client.name}`}
        description="Contexto, conhecimento e regras do cliente. Nada entra em vigor sem aprovação."
      />
      {conflictingSubjects.length > 0 ? (
        <div
          role="alert"
          className="mb-6 rounded-lg border border-status-danger bg-status-danger-surface p-4 text-sm text-status-danger"
        >
          <p className="font-medium">Conflito de regras: {conflictingSubjects.join(', ')}</p>
          <p className="mt-1">
            Regras em conflito ficam fora das regras efetivas até que alguém rejeite ou substitua um
            dos lados.{' '}
            <Link href={`${context.basePath}/rules`} className="font-medium underline">
              Resolver em Regras
            </Link>
          </p>
        </div>
      ) : null}
      <BrainTabs basePath={context.basePath} />
      {children}
    </>
  );
}
