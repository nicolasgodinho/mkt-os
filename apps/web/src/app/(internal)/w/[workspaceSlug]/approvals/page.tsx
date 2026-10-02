import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { EmptyState, PageHeader, StatusBadge } from '@jmos/ui';
import { requireSessionUser } from '@/lib/auth/session';
import { APPROVAL_STATUS, APPROVAL_STATUSES, type ApprovalStatus } from '@/lib/collab/model';
import { listClientApprovals } from '@/lib/collab/queries';
import { listContents } from '@/lib/content/queries';
import {
  getWorkspaceBySlug,
  getWorkspaceCapabilities,
  listWorkspaceClients,
} from '@/lib/identity/queries';
import { formatDateTime } from '@/lib/jobs/model';

export const metadata: Metadata = { title: 'Aprovações' };

const TABS: { status: ApprovalStatus; label: string }[] = [
  { status: 'requested', label: 'Aguardando cliente' },
  { status: 'changes_requested', label: 'Alterações pedidas' },
  { status: 'approved', label: 'Aprovados' },
];

/** Approvals (docs/07 §9): what is with the client, what came back, what was approved. */
export default async function ApprovalsPage({
  params,
  searchParams,
}: {
  params: Promise<{ workspaceSlug: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { workspaceSlug } = await params;
  await requireSessionUser(`/w/${workspaceSlug}/approvals`);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  if (!(await getWorkspaceCapabilities(workspace.id)).includes('client.view')) notFound();
  const raw = (await searchParams).status;
  const status: ApprovalStatus =
    APPROVAL_STATUSES.find((value) => value === (Array.isArray(raw) ? raw[0] : raw)) ?? 'requested';

  const clients = await listWorkspaceClients(workspace.id);
  const approvals = await listClientApprovals(
    clients.map((client) => client.id),
    status,
  );
  const clientName = new Map(clients.map((client) => [client.id, client.name]));
  const contentIds = new Set(approvals.map((request) => request.content_id));
  const contents = (
    await Promise.all(
      [...new Set(approvals.map((request) => request.client_id))].map((clientId) =>
        listContents(clientId),
      ),
    )
  )
    .flat()
    .filter((content) => contentIds.has(content.id));
  const contentTitle = new Map(contents.map((content) => [content.id, content.title]));
  const base = `/w/${workspace.slug}/approvals`;

  return (
    <>
      <PageHeader
        title="Aprovações"
        description="Conteúdos enviados aos clientes e as respostas deles."
      />
      <nav aria-label="Filtros de aprovação" className="mb-6 border-b">
        <ul className="-mb-px flex gap-1 overflow-x-auto">
          {TABS.map((tab) => {
            const active = tab.status === status;
            return (
              <li key={tab.status}>
                <Link
                  href={tab.status === 'requested' ? base : `${base}?status=${tab.status}`}
                  aria-current={active ? 'page' : undefined}
                  className={
                    active
                      ? 'inline-flex h-9 items-center border-b-2 border-primary px-3 text-sm font-medium'
                      : 'inline-flex h-9 items-center border-b-2 border-transparent px-3 text-sm text-muted-foreground hover:text-foreground'
                  }
                >
                  {tab.label}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>
      {approvals.length === 0 ? (
        <EmptyState
          title="Nada por aqui"
          description="Nenhum pedido de aprovação com este status."
        />
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Pedidos de aprovação">
          {approvals.map((request) => (
            <li
              key={request.id}
              className="flex flex-wrap items-center gap-2 rounded-lg border bg-surface p-3"
            >
              <Link
                href={`/w/${workspace.slug}/clients/${request.client_id}/content/items/${request.content_id}`}
                className="text-sm font-medium text-primary"
              >
                {contentTitle.get(request.content_id) ?? 'Conteúdo'}
              </Link>
              <StatusBadge tone={APPROVAL_STATUS[request.status].tone}>
                {APPROVAL_STATUS[request.status].label}
              </StatusBadge>
              <span className="text-xs text-muted-foreground">
                {clientName.get(request.client_id) ?? ''} · pedido em{' '}
                {formatDateTime(request.requested_at)}
                {request.due_at ? ` · prazo ${formatDateTime(request.due_at) ?? ''}` : ''}
              </span>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
