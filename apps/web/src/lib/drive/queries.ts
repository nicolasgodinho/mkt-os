import 'server-only';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  connectionSchema,
  fileSchema,
  syncJobSchema,
  type DriveConnection,
  type DriveFile,
  type SyncJob,
} from './model';

/** Drive registry reads with the user's session (RLS: internal staff of the client only). */

class DriveDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`drive data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'DriveDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new DriveDataError('client unavailable', 'not_configured');
  return supabase;
}

export async function getConnection(clientId: string): Promise<DriveConnection | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('integration_connections')
    .select(
      'id, client_id, provider, status, root_folder_id, credential_ref, sync_interval_minutes, last_success_at',
    )
    .eq('client_id', clientId)
    .eq('provider', 'google_drive')
    .maybeSingle();
  if (error !== null) throw new DriveDataError('connection', error.code);
  return data === null ? null : connectionSchema.parse(data);
}

export const FILES_LIMIT = 500;

export async function listFiles(
  connectionId: string,
  includeRemoved: boolean,
): Promise<DriveFile[]> {
  const supabase = await reader();
  let query = supabase
    .from('file_records')
    .select(
      'id, drive_file_id, name, mime_type, drive_revision, modified_at, size_bytes, sync_status, index_status, last_seen_at',
    )
    .eq('connection_id', connectionId);
  if (!includeRemoved) query = query.eq('sync_status', 'synced');
  const { data, error } = await query.order('name').limit(FILES_LIMIT);
  if (error !== null) throw new DriveDataError('files', error.code);
  return z.array(fileSchema).parse(data);
}

/** The most recent sync job of a connection (where its failure state lives). */
export async function latestSyncJob(connectionId: string): Promise<SyncJob | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('jobs')
    .select('id, status, attempts, run_after, last_error, finished_at, created_at')
    .eq('type', 'drive.sync')
    .eq('input->>connection_id', connectionId)
    .order('created_at', { ascending: false })
    .limit(1);
  if (error !== null) throw new DriveDataError('sync job', error.code);
  return z.array(syncJobSchema).parse(data)[0] ?? null;
}
