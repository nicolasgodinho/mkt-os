import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { RULE_TYPE_LABELS } from '@/lib/brain/model';
import { capabilityFlags } from '@/lib/content/access';
import { completeReview, recordRuleCheck, saveContent } from '@/lib/content/actions';
import {
  CONTENT_STATUS,
  RULE_CHECK,
  RULE_CHECK_RESULTS,
  type ContentPayload,
} from '@/lib/content/model';
import { getContent, getPauta, getRevisionValidation, listRevisions } from '@/lib/content/queries';
import { isUuid } from '@/lib/identity/routing';
import { formatDateTime } from '@/lib/jobs/model';

export const metadata: Metadata = { title: 'Content Studio' };

function Preview({ payload, label }: { payload: ContentPayload; label: string }) {
  return (
    <article aria-label={label} className="rounded-lg border bg-surface p-4">
      {payload.headline ? <p className="text-base font-semibold">{payload.headline}</p> : null}
      <p className="mt-1 text-sm whitespace-pre-line">{payload.body ?? 'Sem texto.'}</p>
      {payload.cta ? <p className="mt-2 text-sm font-medium">{payload.cta}</p> : null}
      {payload.hashtags && payload.hashtags.length > 0 ? (
        <p className="mt-2 text-xs text-muted-foreground">{payload.hashtags.join(' ')}</p>
      ) : null}
    </article>
  );
}

/**
 * Content Studio (docs/07 §8): working payload, preview, immutable revisions, rule validation and
 * internal review. Approval always shows and targets the exact revision under review.
 */
export default async function ContentStudioPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string; contentId: string }>;
}) {
  const { workspaceSlug, clientId, contentId } = await params;
  const { workspace, client } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/content/items/${contentId}`,
  );
  if (!isUuid(contentId)) notFound();
  const content = await getContent(client.id, contentId);
  if (content === null) notFound();
  const can = await capabilityFlags(workspace.id);
  const [pauta, revisions] = await Promise.all([
    getPauta(client.id, content.pauta_id),
    listRevisions(content.id),
  ]);
  const underReview = content.status === 'internal_review' && content.current_revision_id !== null;
  const validation =
    underReview && content.current_revision_id !== null
      ? await getRevisionValidation(content.current_revision_id)
      : [];
  const current = revisions.find((revision) => revision.id === content.current_revision_id);
  const approved = revisions.find((revision) => revision.id === content.approved_revision_id);
  const blocking = validation.filter((row) => row.blocking).length;
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };
  const base = `/w/${workspace.slug}/clients/${client.id}/content`;
  const editable = ['ready', 'producing', 'internal_review', 'approved'].includes(content.status);
  const payload = content.working_payload;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-lg font-semibold">{content.title}</h2>
          <StatusBadge tone={CONTENT_STATUS[content.status].tone}>
            {CONTENT_STATUS[content.status].label}
          </StatusBadge>
        </div>
        <p className="mt-1 text-xs text-muted-foreground">
          {content.channel} · {content.format} · pauta:{' '}
          {pauta ? (
            <Link href={`${base}/pautas/${pauta.id}`} className="underline">
              {pauta.title}
            </Link>
          ) : (
            '—'
          )}
          {approved ? ` · aprovado na revisão ${approved.revision_number.toString()}` : ''}
        </p>
      </div>

      {underReview && current ? (
        <section
          aria-labelledby="section-review"
          className="rounded-lg border border-status-warning p-4"
        >
          <h3 id="section-review" className="text-sm font-medium">
            Revisão interna: revisão {current.revision_number.toString()}
          </h3>
          <p className="mt-1 text-xs text-muted-foreground">
            Toda regra obrigatória ou proibitiva ativa para este cliente e canal precisa ser checada
            nesta revisão. Uma violação, uma regra sem checagem ou um conflito de regras impede a
            aprovação.
          </p>
          <Preview
            payload={current.payload}
            label={`Revisão ${current.revision_number.toString()}`}
          />
          {validation.length === 0 ? (
            <p className="mt-3 text-sm text-muted-foreground">
              Nenhuma regra obrigatória ou proibitiva se aplica.
            </p>
          ) : (
            <ul className="mt-3 flex flex-col gap-2" aria-label="Validação de regras">
              {validation.map((row) => (
                <li key={row.rule_id} className="rounded-md border bg-surface p-3">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <StatusBadge tone={row.type === 'MUST_NOT' ? 'danger' : 'info'}>
                      {RULE_TYPE_LABELS[row.type]}
                    </StatusBadge>
                    {row.subject ? (
                      <span className="text-xs font-medium">{row.subject}</span>
                    ) : null}
                    {row.result ? (
                      <StatusBadge tone={RULE_CHECK[row.result].tone}>
                        {RULE_CHECK[row.result].label}
                      </StatusBadge>
                    ) : (
                      <StatusBadge tone="warning">Sem checagem</StatusBadge>
                    )}
                    {row.blocking ? <StatusBadge tone="danger">Bloqueia</StatusBadge> : null}
                  </div>
                  <p className="mt-1 text-sm">{row.statement}</p>
                  {can.review ? (
                    <ActionForm
                      action={recordRuleCheck}
                      hidden={{ ...scope, revisionId: current.id, ruleId: row.rule_id }}
                      buttons={RULE_CHECK_RESULTS.map((result) => ({
                        label: RULE_CHECK[result].label,
                        value: result,
                        variant:
                          result === 'violation' ? ('secondary' as const) : ('ghost' as const),
                        ariaLabel: `${RULE_CHECK[result].label}: ${row.statement.slice(0, 60)}`,
                      }))}
                      pendingLabel="Enviando…"
                      variant="inline"
                      className="mt-2"
                    >
                      <TextField
                        id={`note-${row.rule_id}`}
                        name="note"
                        label={`Observação sobre ${row.subject ?? 'esta regra'} (opcional)`}
                        maxLength={1000}
                      />
                    </ActionForm>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}

      {can.review && content.current_revision_id !== null ? (
        // Always mounted (buttons only while under review) so the decision result stays visible
        // after the section above disappears.
        <section aria-labelledby="section-decision" className="rounded-lg border bg-surface p-4">
          <h3 id="section-decision" className="text-sm font-medium">
            Decisão da revisão interna
          </h3>
          <ActionForm
            action={completeReview}
            hidden={{ ...scope, revisionId: content.current_revision_id }}
            buttons={
              underReview
                ? [
                    {
                      label: 'Aprovar esta revisão',
                      value: 'approve',
                      disabled: blocking > 0,
                      describedBy: 'review-hint',
                    },
                    { label: 'Pedir alterações', value: 'changes', variant: 'secondary' },
                  ]
                : []
            }
            pendingLabel="Enviando…"
            className="mt-2"
          >
            <p id="review-hint" className="text-xs text-muted-foreground">
              {!underReview
                ? 'Nenhuma revisão aguardando decisão.'
                : blocking > 0
                  ? `${blocking.toString()} regra(s) bloqueando a aprovação.`
                  : 'Nenhuma regra bloqueando. A aprovação vale para esta revisão exata.'}
            </p>
          </ActionForm>
        </section>
      ) : null}

      <section aria-labelledby="section-editor" className="rounded-lg border bg-surface p-4">
        <h3 id="section-editor" className="text-sm font-medium">
          Texto de trabalho
        </h3>
        {can.edit && editable ? (
          <ActionForm
            action={saveContent}
            hidden={{ ...scope, id: content.id }}
            buttons={[
              { label: 'Salvar rascunho', value: 'save', variant: 'secondary' },
              { label: 'Salvar e enviar para revisão', value: 'submit' },
            ]}
            className="mt-3 max-w-2xl"
          >
            {content.status === 'approved' || content.status === 'internal_review' ? (
              <p className="text-xs text-status-warning">
                Editar agora volta o conteúdo para produção. A revisão{' '}
                {content.status === 'approved' ? 'aprovada' : 'em análise'} continua guardada sem
                alteração.
              </p>
            ) : null}
            <TextField
              id="payload-headline"
              name="headline"
              label="Título do post"
              maxLength={500}
              defaultValue={payload.headline ?? ''}
            />
            <TextAreaField
              id="payload-body"
              name="body"
              label="Texto"
              rows={8}
              maxLength={10000}
              defaultValue={payload.body ?? ''}
            />
            <TextField
              id="payload-cta"
              name="cta"
              label="Chamada para ação"
              maxLength={300}
              defaultValue={payload.cta ?? ''}
            />
            <TextField
              id="payload-hashtags"
              name="hashtags"
              label="Hashtags (separadas por espaço)"
              maxLength={4000}
              defaultValue={(payload.hashtags ?? []).join(' ')}
            />
            <TextField
              id="payload-alt"
              name="alt_text"
              label="Texto alternativo da imagem"
              maxLength={2000}
              defaultValue={payload.alt_text ?? ''}
            />
          </ActionForm>
        ) : (
          <div className="mt-3">
            <Preview payload={payload} label="Texto de trabalho" />
          </div>
        )}
      </section>

      <section aria-labelledby="section-revisions">
        <h3 id="section-revisions" className="mb-3 text-sm font-medium">
          Revisões
        </h3>
        {revisions.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhuma revisão ainda.</p>
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Histórico de revisões">
            {revisions.map((revision) => (
              <li key={revision.id} className="rounded-lg border bg-surface p-3 text-sm">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="font-medium">Revisão {revision.revision_number.toString()}</span>
                  {revision.id === content.approved_revision_id ? (
                    <StatusBadge tone="success">Aprovada</StatusBadge>
                  ) : null}
                  {revision.id === content.current_revision_id ? (
                    <StatusBadge tone="info">Mais recente</StatusBadge>
                  ) : null}
                  <span className="text-xs text-muted-foreground">
                    {formatDateTime(revision.created_at)} · hash{' '}
                    {revision.immutable_hash.slice(0, 12)}
                  </span>
                </div>
                <p className="mt-1 line-clamp-2 text-xs text-muted-foreground">
                  {revision.payload.body ?? ''}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
