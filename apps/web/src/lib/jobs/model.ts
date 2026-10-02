import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';

/**
 * Job center contract (tests/acceptance/increment-3/README.md) as seen by the web app. The
 * database decides visibility and every action; these are display helpers only.
 */

export const JOB_STATUSES = [
  'queued',
  'running',
  'retry_wait',
  'completed',
  'failed',
  'dead_letter',
  'canceled',
] as const;
export type JobStatus = (typeof JOB_STATUSES)[number];

/** Allow-listed system jobs a workspace manager may request (decision 2). */
export const REQUESTABLE_JOBS = [
  { type: 'system.healthcheck', label: 'Testar worker (healthcheck)' },
  { type: 'ai.model_check', label: 'Testar modelo de IA' },
] as const;

export const JOB_STATUS: Record<JobStatus, { label: string; tone: StatusTone }> = {
  queued: { label: 'Na fila', tone: 'info' },
  running: { label: 'Executando', tone: 'info' },
  retry_wait: { label: 'Aguardando nova tentativa', tone: 'warning' },
  completed: { label: 'Concluído', tone: 'success' },
  failed: { label: 'Falhou', tone: 'danger' },
  dead_letter: { label: 'Esgotou tentativas', tone: 'danger' },
  canceled: { label: 'Cancelado', tone: 'neutral' },
};

export const CANCELABLE: readonly JobStatus[] = ['queued', 'retry_wait'];
export const RETRYABLE: readonly JobStatus[] = ['failed', 'dead_letter', 'canceled'];

export const jobSchema = z.object({
  id: z.uuid(),
  type: z.string(),
  schema_version: z.number().int(),
  client_id: z.uuid().nullable(),
  status: z.enum(JOB_STATUSES),
  attempts: z.number().int(),
  max_attempts: z.number().int(),
  run_after: z.string(),
  lease_until: z.string().nullable(),
  model_profile: z.string().nullable(),
  last_error: z
    .object({ code: z.string().optional(), message: z.string().optional() })
    .loose()
    .nullable(),
  created_at: z.string(),
  finished_at: z.string().nullable(),
});
export type Job = z.infer<typeof jobSchema>;

export const summarySchema = z.object({
  queued: z.number().int(),
  running: z.number().int(),
  stalled: z.number().int(),
  retry_wait: z.number().int(),
  completed: z.number().int(),
  failed: z.number().int(),
  dead_letter: z.number().int(),
  canceled: z.number().int(),
  last_completed_at: z.string().nullable(),
});
export type JobSummary = z.infer<typeof summarySchema>;

export const workerSchema = z.object({
  worker_id: z.string(),
  status: z.enum(['starting', 'idle', 'busy', 'stopping', 'stopped']),
  version: z.string(),
  job_types: z.array(z.string()),
  active_model_profile: z.string().nullable(),
  last_seen_at: z.string(),
});
export type WorkerHeartbeat = z.infer<typeof workerSchema>;

/** A worker heartbeats every 15 s by default; four missed beats means offline. */
export const WORKER_OFFLINE_AFTER_MS = 60_000;

export function isWorkerOnline(worker: WorkerHeartbeat, now: Date = new Date()): boolean {
  if (worker.status === 'stopped') return false;
  return now.getTime() - Date.parse(worker.last_seen_at) < WORKER_OFFLINE_AFTER_MS;
}

/** A running job whose lease expired: its worker died or stalled (ADR 0001). */
export function isStalled(
  job: Pick<Job, 'status' | 'lease_until'>,
  now: Date = new Date(),
): boolean {
  return (
    job.status === 'running' &&
    job.lease_until !== null &&
    Date.parse(job.lease_until) < now.getTime()
  );
}

export function contractKey(job: Pick<Job, 'type' | 'schema_version'>): string {
  return `${job.type}.v${job.schema_version.toString()}`;
}

/** dd/mm/aaaa hh:mm in America/Sao_Paulo (the agency's timezone; see BUSINESS_UTC_OFFSET). */
export function formatDateTime(value: string | null): string | null {
  if (value === null) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(date);
}
