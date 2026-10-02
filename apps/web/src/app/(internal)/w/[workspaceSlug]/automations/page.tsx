import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Button, EmptyState, PageHeader, SelectField, StatusBadge } from '@jmos/ui';
import { ActionForm, type ActionFormButton } from '@/components/action-form';
import { requireSessionUser } from '@/lib/auth/session';
import { getWorkspaceBySlug, getWorkspaceCapabilities } from '@/lib/identity/queries';
import { manageJob, requestSystemJob } from '@/lib/jobs/actions';
import {
  CANCELABLE,
  JOB_STATUS,
  JOB_STATUSES,
  REQUESTABLE_JOBS,
  RETRYABLE,
  contractKey,
  formatDateTime,
  isStalled,
  isWorkerOnline,
  type JobStatus,
} from '@/lib/jobs/model';
import { RECENT_JOBS_LIMIT, getJobSummary, listRecentJobs, listWorkers } from '@/lib/jobs/queries';

export const metadata: Metadata = { title: 'Automações' };

function parseStatus(value: string | string[] | undefined): JobStatus | null {
  const raw = Array.isArray(value) ? value[0] : value;
  return JOB_STATUSES.find((status) => status === raw) ?? null;
}

/**
 * Job center (docs/15 "AI worker health"; docs/03 journey G): worker liveness, per-status counts,
 * recent jobs and safe cancel/retry. Internal-only; actions need `workspace.manage`.
 */
export default async function AutomationsPage({
  params,
  searchParams,
}: {
  params: Promise<{ workspaceSlug: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { workspaceSlug } = await params;
  await requireSessionUser(`/w/${workspaceSlug}/automations`);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  const capabilities = await getWorkspaceCapabilities(workspace.id);
  if (!capabilities.includes('client.view')) notFound();
  const canManage = capabilities.includes('workspace.manage');
  const status = parseStatus((await searchParams).status);

  const [summary, jobs, workers] = await Promise.all([
    getJobSummary(workspace.id),
    listRecentJobs(workspace.id, status),
    listWorkers(),
  ]);
  const onlineWorkers = workers.filter((worker) => isWorkerOnline(worker));
  const basePath = `/w/${workspace.slug}/automations`;

  const counts = summary
    ? [
        { label: 'Na fila', value: summary.queued },
        { label: 'Executando', value: summary.running },
        { label: 'Travados', value: summary.stalled },
        { label: 'Aguardando nova tentativa', value: summary.retry_wait },
        { label: 'Concluídos', value: summary.completed },
        { label: 'Falharam', value: summary.failed },
        { label: 'Esgotaram tentativas', value: summary.dead_letter },
        { label: 'Cancelados', value: summary.canceled },
      ]
    : [];

  return (
    <div className="flex flex-col gap-6">
      <PageHeader
        title="Automações"
        description="Central de jobs: saúde do AI Worker e processamentos em segundo plano."
        actions={
          <Link
            href={status === null ? basePath : `${basePath}?status=${status}`}
            className="text-sm font-medium text-primary"
          >
            Atualizar
          </Link>
        }
      />

      <section aria-labelledby="section-workers" className="rounded-lg border bg-surface p-4">
        <h2 id="section-workers" className="text-sm font-medium">
          AI Worker
        </h2>
        {onlineWorkers.length === 0 ? (
          <p role="status" className="mt-2 text-sm text-status-warning">
            Nenhum worker online. Os jobs ficam na fila e são processados quando um worker se
            conectar; o portal e o restante do sistema continuam funcionando.
          </p>
        ) : null}
        {workers.length === 0 ? null : (
          <ul className="mt-3 divide-y">
            {workers.map((worker) => {
              const online = isWorkerOnline(worker);
              return (
                <li
                  key={worker.worker_id}
                  className="flex flex-wrap items-center gap-2 py-2 text-sm"
                >
                  <span className="font-medium">{worker.worker_id}</span>
                  <StatusBadge tone={online ? 'success' : 'neutral'}>
                    {online ? 'Online' : 'Offline'}
                  </StatusBadge>
                  <span className="text-xs text-muted-foreground">
                    v{worker.version} · perfil ativo: {worker.active_model_profile ?? 'nenhum'} ·
                    visto em {formatDateTime(worker.last_seen_at)}
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {summary ? (
        <section aria-labelledby="section-summary">
          <h2 id="section-summary" className="mb-3 text-sm font-medium">
            Resumo
          </h2>
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {counts.map((count) => (
              <div key={count.label} className="rounded-lg border bg-surface p-3">
                <dt className="text-xs text-muted-foreground">{count.label}</dt>
                <dd className="mt-1 text-xl font-semibold tabular-nums">{count.value}</dd>
              </div>
            ))}
          </dl>
          <p className="mt-2 text-xs text-muted-foreground">
            Último job concluído: {formatDateTime(summary.last_completed_at) ?? 'nenhum ainda'}
          </p>
        </section>
      ) : null}

      {canManage ? (
        <section aria-labelledby="section-request" className="rounded-lg border bg-surface p-4">
          <h2 id="section-request" className="text-sm font-medium">
            Testes do sistema
          </h2>
          <div className="mt-3 flex flex-wrap gap-4">
            {REQUESTABLE_JOBS.map((job) => (
              <ActionForm
                key={job.type}
                action={requestSystemJob}
                hidden={{
                  workspaceSlug: workspace.slug,
                  workspaceId: workspace.id,
                  type: job.type,
                  idempotencyKey: crypto.randomUUID(),
                }}
                buttons={[{ label: job.label, variant: 'secondary' }]}
                pendingLabel="Enviando…"
                variant="inline"
              />
            ))}
          </div>
        </section>
      ) : null}

      <section aria-labelledby="section-jobs">
        <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
          <h2 id="section-jobs" className="text-sm font-medium">
            Jobs recentes
          </h2>
          <form method="get" aria-label="Filtrar jobs" className="flex items-end gap-2">
            <SelectField
              id="filter-status"
              name="status"
              label="Status"
              defaultValue={status ?? ''}
              options={[
                { value: '', label: 'Todos' },
                ...JOB_STATUSES.map((s) => ({ value: s, label: JOB_STATUS[s].label })),
              ]}
            />
            <Button type="submit" variant="secondary">
              Filtrar
            </Button>
          </form>
        </div>
        {jobs.length === 0 ? (
          <EmptyState
            headingLevel={3}
            title="Nenhum job"
            description={
              status === null
                ? 'Os processamentos em segundo plano deste workspace aparecem aqui.'
                : 'Nenhum job com este status.'
            }
          />
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Jobs">
            {jobs.map((job) => {
              const stalled = isStalled(job);
              const buttons: ActionFormButton[] = [];
              const label = `${contractKey(job)} de ${formatDateTime(job.created_at) ?? ''}`;
              if (CANCELABLE.includes(job.status)) {
                buttons.push({
                  label: 'Cancelar',
                  value: 'cancel',
                  ariaLabel: `Cancelar job ${label}`,
                  variant: 'secondary',
                });
              }
              if (RETRYABLE.includes(job.status)) {
                buttons.push({
                  label: 'Tentar de novo',
                  value: 'retry',
                  ariaLabel: `Tentar de novo job ${label}`,
                });
              }
              return (
                <li key={job.id} className="rounded-lg border bg-surface p-3">
                  <div className="flex flex-wrap items-center gap-1.5">
                    <span className="font-mono text-xs">{contractKey(job)}</span>
                    <StatusBadge tone={JOB_STATUS[job.status].tone}>
                      {JOB_STATUS[job.status].label}
                    </StatusBadge>
                    {stalled ? <StatusBadge tone="danger">Travado</StatusBadge> : null}
                  </div>
                  <p className="mt-1 text-xs text-muted-foreground">
                    Criado em {formatDateTime(job.created_at)} · tentativa {job.attempts.toString()}{' '}
                    de {job.max_attempts.toString()}
                    {job.model_profile ? ` · perfil ${job.model_profile}` : ''}
                    {job.client_id ? ' · job de cliente' : ' · job do workspace'}
                  </p>
                  {job.last_error ? (
                    <p className="mt-1 text-xs text-status-danger">
                      Erro: {job.last_error.code ?? 'desconhecido'}
                      {job.last_error.message ? `: ${job.last_error.message}` : ''}
                    </p>
                  ) : null}
                  {canManage ? (
                    <ActionForm
                      action={manageJob}
                      hidden={{ workspaceSlug: workspace.slug, id: job.id }}
                      buttons={buttons}
                      pendingLabel="Enviando…"
                      variant="inline"
                      className="mt-2"
                    />
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
        {jobs.length === RECENT_JOBS_LIMIT ? (
          <p className="mt-2 text-xs text-muted-foreground">
            Mostrando os {RECENT_JOBS_LIMIT.toString()} jobs mais recentes.
          </p>
        ) : null}
      </section>
    </div>
  );
}
