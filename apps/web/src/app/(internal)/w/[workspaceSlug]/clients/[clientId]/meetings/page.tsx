import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, PageHeader, StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { formatDateTime } from '@/lib/jobs/model';
import { createMeeting } from '@/lib/meetings/actions';
import { MEETING_STATUS } from '@/lib/meetings/model';
import { listMeetings } from '@/lib/meetings/queries';

export const metadata: Metadata = { title: 'Reuniões' };

/** Client meetings (docs/02 Meeting; docs/07 §11 entry point). Internal-only. */
export default async function MeetingsPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { workspace, client, can } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/meetings`,
  );
  const meetings = await listMeetings(client.id);
  const base = `/w/${workspace.slug}/clients/${client.id}/meetings`;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
          <Link href={`/w/${workspace.slug}/clients`} className="hover:text-foreground">
            Clientes
          </Link>
          <span aria-hidden> / </span>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}`}
            className="hover:text-foreground"
          >
            {client.name}
          </Link>
        </nav>
        <PageHeader
          title={`Reuniões: ${client.name}`}
          description="Transcrições e conhecimento extraído para revisão. Nada entra no Client Brain sem uma pessoa aceitar."
        />
      </div>

      {meetings.length === 0 ? (
        <EmptyState
          title="Nenhuma reunião ainda"
          description="Registre uma reunião, cole a transcrição ou aponte a gravação, e peça a extração."
        />
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Reuniões">
          {meetings.map((meeting) => (
            <li key={meeting.id} className="rounded-lg border bg-surface p-3">
              <div className="flex flex-wrap items-center gap-2">
                <Link href={`${base}/${meeting.id}`} className="text-sm font-medium text-primary">
                  {meeting.title}
                </Link>
                <StatusBadge tone={MEETING_STATUS[meeting.processing_status].tone}>
                  {MEETING_STATUS[meeting.processing_status].label}
                </StatusBadge>
              </div>
              <p className="mt-1 text-xs text-muted-foreground">
                {formatDateTime(meeting.starts_at)}
                {meeting.participants.length > 0
                  ? ` · ${meeting.participants.map((p) => p.name).join(', ')}`
                  : ''}
              </p>
            </li>
          ))}
        </ul>
      )}

      {can.propose ? (
        <section aria-labelledby="section-new-meeting" className="rounded-lg border bg-surface p-4">
          <h2 id="section-new-meeting" className="text-sm font-medium">
            Nova reunião
          </h2>
          <ActionForm
            action={createMeeting}
            hidden={{ workspaceSlug: workspace.slug, clientId: client.id }}
            buttons={[{ label: 'Criar reunião' }]}
            pendingLabel="Criando…"
            resetOnSuccess
            className="mt-3 max-w-2xl"
          >
            <TextField id="meeting-title" name="title" label="Título" required maxLength={300} />
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField
                id="meeting-starts"
                name="startsAt"
                type="datetime-local"
                label="Início"
                required
              />
              <TextField id="meeting-ends" name="endsAt" type="datetime-local" label="Fim" />
            </div>
            <TextAreaField
              id="meeting-participants"
              name="participants"
              label="Participantes (um por linha)"
              maxLength={12000}
            />
            <TextField
              id="meeting-recording"
              name="recordingRef"
              label="Gravação (opcional): caminho relativo na pasta de mídia do worker"
              placeholder="cliente-a/kickoff.m4a"
              maxLength={500}
            />
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
