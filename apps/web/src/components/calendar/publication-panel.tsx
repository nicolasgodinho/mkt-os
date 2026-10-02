import { StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import {
  cancelPublication,
  markPublished,
  reschedulePublication,
  schedulePublication,
  setProductionDeadline,
} from '@/lib/calendar/actions';
import {
  businessDay,
  PUBLICATION_STATUS,
  toDateTimeLocal,
  type Publication,
} from '@/lib/calendar/model';
import type { Content } from '@/lib/content/model';
import { formatDateTime } from '@/lib/jobs/model';

interface PublicationPanelProps {
  content: Content;
  publications: readonly Publication[];
  scope: { workspaceSlug: string; clientId: string; contentId: string };
  can: { edit: boolean; schedule: boolean; publish: boolean };
}

/**
 * Publication schedule of one content (docs/04 Publication, docs/06 calendar semantics). The
 * production deadline and each publication date are separate fields, changed by separate forms.
 */
export function PublicationPanel({ content, publications, scope, can }: PublicationPanelProps) {
  const schedulable =
    ['approved', 'scheduled', 'published'].includes(content.status) &&
    content.client_approved_revision_id !== null &&
    content.client_approved_revision_id === content.approved_revision_id;

  return (
    <section aria-labelledby="section-publication" className="rounded-lg border bg-surface p-4">
      <h3 id="section-publication" className="text-sm font-medium">
        Publicação
      </h3>

      <div className="mt-3">
        <p className="text-sm">
          Prazo de produção:{' '}
          <span className="font-medium">
            {content.production_due_at === null
              ? 'sem prazo'
              : (formatDateTime(content.production_due_at) ?? '')}
          </span>
        </p>
        {can.edit && !['canceled', 'archived'].includes(content.status) ? (
          <ActionForm
            action={setProductionDeadline}
            hidden={scope}
            buttons={[{ label: 'Salvar prazo', variant: 'secondary' }]}
            variant="inline"
            className="mt-2"
          >
            <TextField
              id="production-due"
              name="dueAt"
              type="date"
              label="Prazo de produção"
              defaultValue={
                content.production_due_at === null ? '' : businessDay(content.production_due_at)
              }
              className="max-w-48"
            />
          </ActionForm>
        ) : null}
      </div>

      {publications.length === 0 ? (
        <p className="mt-4 text-sm text-muted-foreground">Nenhuma publicação agendada.</p>
      ) : (
        <ul className="mt-4 flex flex-col gap-3" aria-label="Publicações">
          {publications.map((publication) => {
            const hidden = { ...scope, publicationId: publication.id };
            return (
              <li key={publication.id} className="rounded-md border p-3 text-sm">
                <div className="flex flex-wrap items-center gap-1.5">
                  <StatusBadge tone={PUBLICATION_STATUS[publication.status].tone}>
                    {PUBLICATION_STATUS[publication.status].label}
                  </StatusBadge>
                  <span className="font-medium">{publication.channel}</span>
                  <span className="text-xs text-muted-foreground">
                    {formatDateTime(publication.scheduled_at)}
                    {publication.published_at
                      ? ` · publicada em ${formatDateTime(publication.published_at) ?? ''}`
                      : ''}
                  </span>
                  {publication.remote_url ? (
                    <a
                      href={publication.remote_url}
                      target="_blank"
                      rel="noopener noreferrer nofollow"
                      className="text-xs text-primary underline"
                    >
                      Ver publicação
                    </a>
                  ) : null}
                </div>
                {publication.status === 'scheduled' && can.schedule ? (
                  <div className="mt-2 flex flex-col gap-2">
                    <ActionForm
                      action={reschedulePublication}
                      hidden={hidden}
                      buttons={[{ label: 'Mudar data da publicação', variant: 'secondary' }]}
                      variant="inline"
                    >
                      <TextField
                        id={`reschedule-${publication.id}`}
                        name="scheduledAt"
                        type="datetime-local"
                        label="Nova data de publicação"
                        defaultValue={toDateTimeLocal(publication.scheduled_at)}
                        required
                      />
                    </ActionForm>
                    <ActionForm
                      action={cancelPublication}
                      hidden={hidden}
                      buttons={[{ label: 'Cancelar publicação', variant: 'secondary' }]}
                      variant="inline"
                    />
                  </div>
                ) : null}
                {publication.status === 'scheduled' && can.publish ? (
                  <ActionForm
                    action={markPublished}
                    hidden={hidden}
                    buttons={[{ label: 'Registrar como publicada' }]}
                    variant="inline"
                    className="mt-2"
                  >
                    <TextField
                      id={`remote-${publication.id}`}
                      name="remoteUrl"
                      type="url"
                      label="Link da publicação (opcional)"
                      placeholder="https://"
                    />
                  </ActionForm>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      {can.schedule ? (
        schedulable ? (
          <ActionForm
            action={schedulePublication}
            hidden={scope}
            buttons={[{ label: 'Agendar publicação' }]}
            pendingLabel="Agendando…"
            className="mt-4 max-w-md"
          >
            <TextField
              id="schedule-at"
              name="scheduledAt"
              type="datetime-local"
              label="Data e hora da publicação"
              required
            />
            <TextField
              id="schedule-channel"
              name="channel"
              label="Canal"
              defaultValue={content.channel}
            />
          </ActionForm>
        ) : (
          <p className="mt-4 text-xs text-muted-foreground">
            Só é possível agendar depois que o cliente aprovar a versão aprovada mais recente.
          </p>
        )
      ) : null}
    </section>
  );
}
