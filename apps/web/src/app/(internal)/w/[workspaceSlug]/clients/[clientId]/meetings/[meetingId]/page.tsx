import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { EmptyState, PageHeader, StatusBadge, TextAreaField } from '@jmos/ui';
import { ActionForm, type ActionFormButton } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { isUuid } from '@/lib/identity/routing';
import { JOB_STATUS, formatDateTime } from '@/lib/jobs/model';
import { requestMeetingJob, reviewProposal, saveTranscript } from '@/lib/meetings/actions';
import {
  MEETING_STATUS,
  PROPOSAL_KIND_LABELS,
  PROPOSAL_KINDS,
  PROPOSAL_STATUS,
  brainSectionFor,
  formatConfidence,
} from '@/lib/meetings/model';
import {
  getLatestTranscript,
  getMeeting,
  listMeetingJobs,
  listProposals,
} from '@/lib/meetings/queries';

export const metadata: Metadata = { title: 'Revisão da reunião' };

/**
 * Meeting Intelligence Review (docs/07 §11): transcript, processing and the proposals extracted by
 * the local AI. Accepting sends a proposal to the Client Brain as PROPOSED knowledge; approval and
 * rule activation remain separate steps there (TEST_SPEC decision 2).
 */
export default async function MeetingReviewPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string; meetingId: string }>;
}) {
  const { workspaceSlug, clientId, meetingId } = await params;
  const { workspace, client, can } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/meetings/${meetingId}`,
  );
  if (!isUuid(meetingId)) notFound();
  const meeting = await getMeeting(client.id, meetingId);
  if (meeting === null) notFound();
  const [transcript, proposals, jobs] = await Promise.all([
    getLatestTranscript(meeting.id),
    listProposals(meeting.id),
    listMeetingJobs(meeting.id),
  ]);

  const scope = { workspaceSlug: workspace.slug, clientId: client.id, meetingId: meeting.id };
  const brainBase = `/w/${workspace.slug}/clients/${client.id}/brain`;
  const pending = proposals.filter((proposal) => proposal.status === 'proposed').length;
  const latestJob = jobs[0];
  const lastJobFailed =
    latestJob !== undefined && ['failed', 'dead_letter'].includes(latestJob.status);
  const jobButtons: ActionFormButton[] = [];
  if (transcript !== null) {
    jobButtons.push({ label: 'Extrair conhecimento', value: 'extract' });
  }
  if (meeting.recording_ref !== null) {
    jobButtons.push({ label: 'Transcrever gravação', value: 'transcribe', variant: 'secondary' });
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}`}
            className="hover:text-foreground"
          >
            {client.name}
          </Link>
          <span aria-hidden> / </span>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}/meetings`}
            className="hover:text-foreground"
          >
            Reuniões
          </Link>
        </nav>
        <PageHeader
          title={meeting.title}
          description={`${formatDateTime(meeting.starts_at) ?? ''}${
            meeting.participants.length > 0
              ? ` · ${meeting.participants.map((p) => p.name).join(', ')}`
              : ''
          }`}
          actions={
            <>
              <StatusBadge tone={MEETING_STATUS[meeting.processing_status].tone}>
                {MEETING_STATUS[meeting.processing_status].label}
              </StatusBadge>
              {lastJobFailed ? (
                <StatusBadge tone="danger">Último processamento falhou</StatusBadge>
              ) : null}
            </>
          }
        />
      </div>

      <section aria-labelledby="section-processing" className="rounded-lg border bg-surface p-4">
        <h2 id="section-processing" className="text-sm font-medium">
          Processamento
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          Gravação: {meeting.recording_ref ?? 'não informada'} · Transcrição:{' '}
          {transcript === null
            ? 'nenhuma'
            : `revisão ${transcript.revision.toString()} (${transcript.origin === 'manual' ? 'colada' : 'automática'})`}
        </p>
        {jobs.length > 0 ? (
          <ul className="mt-2 flex flex-col gap-1 text-xs" aria-label="Jobs desta reunião">
            {jobs.map((job) => (
              <li key={job.id} className="flex flex-wrap items-center gap-1.5">
                <span className="font-mono">{job.type}</span>
                <StatusBadge tone={JOB_STATUS[job.status].tone}>
                  {JOB_STATUS[job.status].label}
                </StatusBadge>
                <span className="text-muted-foreground">{formatDateTime(job.created_at)}</span>
                {job.last_error?.code ? (
                  <span className="text-status-danger">Último erro: {job.last_error.code}</span>
                ) : null}
              </li>
            ))}
          </ul>
        ) : null}
        {can.propose && jobButtons.length > 0 ? (
          <ActionForm
            action={requestMeetingJob}
            hidden={scope}
            buttons={jobButtons}
            pendingLabel="Enviando…"
            variant="inline"
            className="mt-3"
          />
        ) : null}
        <p className="mt-2 text-xs text-muted-foreground">
          O AI Worker processa os jobs localmente. Se ele estiver offline, o pedido fica na fila (
          <Link href={`/w/${workspace.slug}/automations`} className="underline">
            ver Automações
          </Link>
          ).
        </p>
      </section>

      <section aria-labelledby="section-proposals">
        <h2 id="section-proposals" className="mb-1 text-sm font-medium">
          Propostas extraídas
        </h2>
        <p className="mb-3 text-xs text-muted-foreground">
          {pending.toString()} para revisar. Aceitar envia ao Client Brain como proposta; aprovar
          conhecimento e ativar regras continua lá, com as permissões de cada um.
        </p>
        {proposals.length === 0 ? (
          <EmptyState
            headingLevel={3}
            title="Nenhuma proposta"
            description="Salve a transcrição e peça a extração de conhecimento."
          />
        ) : (
          PROPOSAL_KINDS.map((kind) => {
            const items = proposals.filter((proposal) => proposal.kind === kind);
            if (items.length === 0) return null;
            return (
              <div key={kind} className="mb-4">
                <h3 className="mb-2 text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                  {PROPOSAL_KIND_LABELS[kind]}
                </h3>
                <ul className="flex flex-col gap-2" aria-label={PROPOSAL_KIND_LABELS[kind]}>
                  {items.map((proposal) => {
                    const section = brainSectionFor(proposal.kind);
                    const open = proposal.status === 'proposed';
                    const buttons: ActionFormButton[] = [];
                    if (open && proposal.kind !== 'task') {
                      buttons.push({
                        label: 'Aceitar',
                        value: 'accept',
                        ariaLabel: `Aceitar: ${proposal.statement.slice(0, 60)}`,
                      });
                    }
                    if (open) {
                      buttons.push({
                        label: 'Rejeitar',
                        value: 'reject',
                        variant: 'secondary',
                        ariaLabel: `Rejeitar: ${proposal.statement.slice(0, 60)}`,
                      });
                    }
                    return (
                      <li
                        key={proposal.id}
                        data-proposal-id={proposal.id}
                        className={
                          open
                            ? 'rounded-lg border border-dashed border-status-warning bg-status-warning-surface/40 p-3'
                            : 'rounded-lg border bg-surface p-3'
                        }
                      >
                        <div className="flex flex-wrap items-center gap-1.5">
                          <StatusBadge tone={PROPOSAL_STATUS[proposal.status].tone}>
                            {PROPOSAL_STATUS[proposal.status].label}
                          </StatusBadge>
                          {proposal.rule_type ? (
                            <StatusBadge tone="neutral">{proposal.rule_type}</StatusBadge>
                          ) : null}
                          {proposal.subject ? (
                            <span className="text-xs font-medium">Assunto: {proposal.subject}</span>
                          ) : null}
                          {proposal.confidence !== null ? (
                            <span className="text-xs text-muted-foreground">
                              confiança {formatConfidence(proposal.confidence)}
                            </span>
                          ) : null}
                        </div>
                        <p className="mt-2 text-sm">{proposal.statement}</p>
                        {proposal.evidence_quote ? (
                          <blockquote className="mt-1 border-l-2 pl-2 text-xs text-muted-foreground">
                            “{proposal.evidence_quote}”
                          </blockquote>
                        ) : null}
                        {proposal.time_ref ? (
                          <p className="mt-1 text-xs text-muted-foreground">
                            Momento: {proposal.time_ref}
                          </p>
                        ) : null}
                        {proposal.status === 'accepted' && section !== null ? (
                          <Link
                            href={`${brainBase}/${section}`}
                            className="mt-2 inline-flex text-xs font-medium text-primary"
                          >
                            Ver no Client Brain
                          </Link>
                        ) : null}
                        {can.propose ? (
                          <ActionForm
                            action={reviewProposal}
                            hidden={{ ...scope, id: proposal.id }}
                            buttons={buttons}
                            pendingLabel="Enviando…"
                            variant="inline"
                            className="mt-2 w-full"
                          >
                            {open && proposal.kind !== 'task' ? (
                              <details className="w-full text-xs">
                                <summary className="cursor-pointer font-medium text-primary">
                                  Editar antes de aceitar
                                </summary>
                                <TextAreaField
                                  id={`statement-${proposal.id}`}
                                  name="statement"
                                  label="Enunciado"
                                  defaultValue={proposal.statement}
                                  maxLength={2000}
                                  className="mt-2"
                                />
                              </details>
                            ) : null}
                            {open && proposal.kind === 'task' ? (
                              <p className="text-xs text-muted-foreground">
                                Tarefas e perguntas ainda não viram itens do sistema (v0.2).
                              </p>
                            ) : null}
                          </ActionForm>
                        ) : null}
                      </li>
                    );
                  })}
                </ul>
              </div>
            );
          })
        )}
      </section>

      <section aria-labelledby="section-transcript" className="rounded-lg border bg-surface p-4">
        <h2 id="section-transcript" className="text-sm font-medium">
          Transcrição
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          A transcrição é tratada como evidência: o que está escrito nela nunca vira instrução para
          o sistema.
        </p>
        {can.propose ? (
          <ActionForm
            action={saveTranscript}
            hidden={scope}
            buttons={[{ label: 'Salvar transcrição' }]}
            pendingLabel="Salvando…"
            className="mt-3"
          >
            <TextAreaField
              id="meeting-transcript"
              name="text"
              label="Texto da transcrição"
              rows={10}
              required
              maxLength={500000}
              defaultValue={transcript?.text ?? ''}
            />
          </ActionForm>
        ) : (
          <p className="mt-3 text-sm whitespace-pre-line">
            {transcript?.text ?? 'Nenhuma transcrição.'}
          </p>
        )}
      </section>
    </div>
  );
}
