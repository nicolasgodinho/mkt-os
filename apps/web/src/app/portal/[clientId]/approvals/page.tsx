import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, PageHeader, StatusBadge } from '@jmos/ui';
import { APPROVAL_STATUS } from '@/lib/collab/model';
import { portalApprovals } from '@/lib/collab/queries';
import { formatDateTime } from '@/lib/jobs/model';
import { requirePortalContext } from '@/lib/portal/context';

export const metadata: Metadata = { title: 'Aprovações' };

/** My Approvals (docs/07 §9 for the client): everything sent to this client for approval. */
export default async function PortalApprovalsPage({
  params,
}: {
  params: Promise<{ clientId: string }>;
}) {
  const { clientId } = await params;
  const { client } = await requirePortalContext(clientId, `/portal/${clientId}/approvals`);
  const rows = await portalApprovals(client.id);

  return (
    <>
      <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
        <Link href={`/portal/${client.id}`}>{client.name}</Link>
      </nav>
      <PageHeader
        title="Aprovações"
        description="Materiais enviados pela equipe para você aprovar."
      />
      {rows.length === 0 ? (
        <EmptyState title="Nenhum material enviado ainda" />
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Materiais para aprovação">
          {rows.map((row) => (
            <li key={row.request_id}>
              <Link
                href={`/portal/${client.id}/approvals/${row.request_id}`}
                className="block rounded-lg border bg-surface px-4 py-3"
              >
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium">{row.content_title}</span>
                  <StatusBadge tone={APPROVAL_STATUS[row.status].tone}>
                    {APPROVAL_STATUS[row.status].label}
                  </StatusBadge>
                </div>
                <p className="mt-1 text-xs text-muted-foreground">
                  {row.channel} · versão {row.revision_number.toString()} · enviado em{' '}
                  {formatDateTime(row.requested_at)}
                </p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
