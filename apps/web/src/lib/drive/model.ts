import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';
import { JOB_STATUSES } from '../jobs/model';

/**
 * Drive sync contract (tests/acceptance/increment-8/README.md) as seen by the web app. Display
 * helpers only: the database decides visibility and every change; the worker talks to Google.
 */

export const connectionSchema = z.object({
  id: z.uuid(),
  client_id: z.uuid(),
  provider: z.literal('google_drive'),
  status: z.enum(['active', 'paused']),
  root_folder_id: z.string(),
  credential_ref: z.string(),
  sync_interval_minutes: z.number().int(),
  last_success_at: z.string().nullable(),
});
export type DriveConnection = z.infer<typeof connectionSchema>;

export const SYNC_STATUSES = ['synced', 'removed'] as const;
export const INDEX_STATUSES = ['pending', 'indexing', 'indexed', 'failed', 'skipped'] as const;

export const fileSchema = z.object({
  id: z.uuid(),
  drive_file_id: z.string(),
  name: z.string(),
  mime_type: z.string(),
  drive_revision: z.string(),
  modified_at: z.string().nullable(),
  size_bytes: z.number().nullable(),
  sync_status: z.enum(SYNC_STATUSES),
  index_status: z.enum(INDEX_STATUSES),
  last_seen_at: z.string(),
});
export type DriveFile = z.infer<typeof fileSchema>;

export const INDEX_STATUS: Record<
  (typeof INDEX_STATUSES)[number],
  { label: string; tone: StatusTone }
> = {
  pending: { label: 'Aguardando indexação', tone: 'warning' },
  indexing: { label: 'Indexando', tone: 'info' },
  indexed: { label: 'Indexado', tone: 'success' },
  failed: { label: 'Falha na indexação', tone: 'danger' },
  skipped: { label: 'Não indexado', tone: 'neutral' },
};

export const syncJobSchema = z.object({
  id: z.uuid(),
  status: z.enum(JOB_STATUSES),
  attempts: z.number().int(),
  run_after: z.string(),
  last_error: z.object({ code: z.string().optional() }).loose().nullable(),
  finished_at: z.string().nullable(),
  created_at: z.string(),
});
export type SyncJob = z.infer<typeof syncJobSchema>;

export type SyncState =
  | { kind: 'paused' }
  | { kind: 'running' }
  | { kind: 'queued' }
  | { kind: 'scheduled'; at: string }
  | { kind: 'retrying'; at: string; code: string | null }
  | { kind: 'failed'; code: string | null }
  | { kind: 'idle' };

/**
 * Where a connection's sync stands, from its status and its latest sync job (failure states live
 * on the job, decision 6). `now` is passed in so the result is deterministic.
 */
export function syncState(
  connection: Pick<DriveConnection, 'status'>,
  latest: SyncJob | null,
  now: Date = new Date(),
): SyncState {
  if (connection.status === 'paused') return { kind: 'paused' };
  if (latest === null) return { kind: 'idle' };
  const code = latest.last_error?.code ?? null;
  switch (latest.status) {
    case 'running':
      return { kind: 'running' };
    case 'queued':
      return new Date(latest.run_after) > now
        ? { kind: 'scheduled', at: latest.run_after }
        : { kind: 'queued' };
    case 'retry_wait':
      return { kind: 'retrying', at: latest.run_after, code };
    case 'failed':
    case 'dead_letter':
      return { kind: 'failed', code };
    default:
      return { kind: 'idle' };
  }
}

/** pt-BR explanation of a worker failure code (apps/ai-worker drive.py). */
const FAILURES = new Map<string, string>([
  [
    'drive_credentials_missing',
    'O worker não tem a credencial desta conexão (JMOS_DRIVE_CREDENTIALS_DIR).',
  ],
  ['drive_credentials_invalid', 'A credencial configurada no worker é inválida.'],
  ['drive_auth_failed', 'O Google recusou a credencial.'],
  ['drive_access_denied', 'A pasta não está compartilhada com a conta de serviço desta conexão.'],
  ['drive_folder_not_found', 'A pasta não foi encontrada no Drive.'],
  ['drive_folder_invalid', 'O ID informado não é de uma pasta.'],
  ['drive_rate_limited', 'Limite de uso do Drive atingido; uma nova tentativa foi agendada.'],
  ['drive_unavailable', 'O Drive não respondeu; uma nova tentativa foi agendada.'],
  ['too_many_files', 'A pasta tem mais de 5000 arquivos: divida-a em pastas menores.'],
  ['too_many_folders', 'A pasta tem subpastas demais.'],
]);

export function failureMessage(code: string | null): string {
  return (code === null ? undefined : FAILURES.get(code)) ?? 'A sincronização falhou.';
}

/** `1.2 MB` style size, or null when Drive does not report one (Google Docs files). */
export function formatSize(bytes: number | null): string | null {
  if (bytes === null) return null;
  if (bytes < 1024) return `${bytes.toString()} B`;
  const units = ['KB', 'MB', 'GB'] as const;
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toLocaleString('pt-BR', { maximumFractionDigits: 1 })} ${units[unit] ?? 'GB'}`;
}

/** Accepts a folder id or a Drive folder link (`…/folders/<id>?usp=sharing`). */
export function extractFolderId(value: string): string {
  const match = /\/folders\/([A-Za-z0-9_-]+)/.exec(value);
  return (match?.[1] ?? value).trim();
}
