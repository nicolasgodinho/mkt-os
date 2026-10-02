import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader, StatusBadge, TextAreaField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { CommentThread } from '@/components/collab/comment-thread';
import { decideApproval } from '@/lib/collab/actions';
import { APPROVAL_STATUS } from '@/lib/collab/model';
import {
  getApprovalRequest,
  getDecision,
  listComments,
  portalApprovals,
} from '@/lib/collab/queries';
import { isUuid } from '@/lib/identity/routing';
import { formatDateTime } from '@/lib/jobs/model';
import { requirePortalContext } from '@/lib/portal/context';

export const metadata: Metadata = { title: 'Aprovar material' };

/**
 * Client Approval Screen (docs/07 §15): large preview of the exact revision, comments, approve or
 * request changes. A request that became stale is shown as canceled.
 */
export default async function PortalApprovalPage({
  params,
}: {
  params: Promise<{ clientId: string; requestId: string }>;
}) {
  const { clientId, requestId } = await params;
  const { client, user, capabilities } = await requirePortalContext(
    clientId,
    `/portal/${clientId}/approvals/${requestId}`,
  );
  if (!isUuid(requestId)) notFound();
  const row = (await portalApprovals(client.id)).find(
    (candidate) => candidate.request_id === requestId,
  );
  const request = await getApprovalRequest(requestId);
  if (row === undefined || request === null) notFound();
  const [decision, comments] = await Promise.all([
    getDecision(request.id),
    listComments(request.content_id),
  ]);
  const open = row.status === 'requested';
  const canDecide = capabilities.includes('approval.decide');
  const canComment = canDecide || capabilities.includes('request.submit');
  const scope = { clientId: client.id, requestId: request.id, contentId: request.content_id };
  const payload = row.payload;

  return (
    <>
      <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
        <Link href={`/portal/${client.id}/approvals`}>Aprovações</Link>
      </nav>
      <PageHeader
        title={row.content_title}
        description={`${row.channel} · ${row.format} · versão ${row.revision_number.toString()}`}
        actions={
          <StatusBadge tone={APPROVAL_STATUS[row.status].tone}>
            {APPROVAL_STATUS[row.status].label}
          </StatusBadge>
        }
      />
      {row.status === 'canceled' ? (
        <p role="status" className="mb-4 rounded-lg border border-status-warning p-3 text-sm">
          Este pedido foi cancelado: a equipe alterou o material ou enviou uma versão nova.
        </p>
      ) : null}

      <article
        aria-label={`Versão ${row.revision_number.toString()}`}
        className="rounded-lg border bg-surface p-4"
      >
        {payload.headline ? <p className="text-lg font-semibold">{payload.headline}</p> : null}
        <p className="mt-2 text-base whitespace-pre-line">{payload.body}</p>
        {payload.cta ? <p className="mt-3 font-medium">{payload.cta}</p> : null}
        {payload.hashtags && payload.hashtags.length > 0 ? (
          <p className="mt-2 text-sm text-muted-foreground">{payload.hashtags.join(' ')}</p>
        ) : null}
      </article>
      <p className="mt-2 text-xs text-muted-foreground">
        Enviado em {formatDateTime(row.requested_at)}
        {row.due_at ? ` · aprovar até ${formatDateTime(row.due_at) ?? ''}` : ''}
      </p>

      {canDecide ? (
        <section aria-labelledby="decision" className="mt-6 rounded-lg border bg-surface p-4">
          <h2 id="decision" className="text-sm font-medium">
            Sua decisão
          </h2>
          {decision ? (
            <p className="mt-1 text-sm">
              {decision.decision === 'approve' ? 'Aprovado' : 'Alterações pedidas'} em{' '}
              {formatDateTime(decision.decided_at)}
              {decision.comment ? `: “${decision.comment}”` : ''}
            </p>
          ) : null}
          <ActionForm
            action={decideApproval}
            hidden={scope}
            buttons={
              open
                ? [
                    { label: 'Aprovar esta versão', value: 'approve' },
                    { label: 'Pedir alterações', value: 'changes', variant: 'secondary' },
                  ]
                : []
            }
            pendingLabel="Enviando…"
            className="mt-3"
          >
            {open ? (
              <TextAreaField
                id="decision-comment"
                name="comment"
                label="Comentário para a equipe (opcional)"
                rows={2}
                maxLength={4000}
              />
            ) : null}
          </ActionForm>
        </section>
      ) : null}

      <div className="mt-6">
        <CommentThread
          title="Conversa com a equipe"
          comments={comments}
          scope={scope}
          visibility="client"
          canWrite={canComment}
          currentUserId={user.id}
        />
      </div>
    </>
  );
}
