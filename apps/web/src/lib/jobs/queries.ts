import 'server-only';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  jobSchema,
  summarySchema,
  workerSchema,
  type Job,
  type JobStatus,
  type JobSummary,
  type WorkerHeartbeat,
} from './model';

/**
 * Job center reads with the signed-in user's session: row level security returns jobs only to
 * internal staff (Increment 0 policy) and worker health only to internal staff.
 */

class JobDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`job center data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'JobDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new JobDataError('client unavailable', 'not_configured');
  return supabase;
}

export async function getJobSummary(workspaceId: string): Promise<JobSummary | null> {
  const supabase = await reader();
  const result = await supabase.rpc('job_center_summary', { p_workspace_id: workspaceId });
  if (result.error !== null) throw new JobDataError('summary', result.error.code);
  const rows = z.array(summarySchema).parse(result.data);
  return rows[0] ?? null;
}

export const RECENT_JOBS_LIMIT = 50;

export async function listRecentJobs(
  workspaceId: string,
  status: JobStatus | null,
): Promise<Job[]> {
  const supabase = await reader();
  let query = supabase
    .from('jobs')
    .select(
      'id, type, schema_version, client_id, status, attempts, max_attempts, run_after, lease_until, model_profile, last_error, created_at, finished_at',
    )
    .eq('workspace_id', workspaceId);
  if (status !== null) query = query.eq('status', status);
  const { data, error } = await query
    .order('created_at', { ascending: false })
    .limit(RECENT_JOBS_LIMIT);
  if (error !== null) throw new JobDataError('jobs', error.code);
  return z.array(jobSchema).parse(data);
}

/** Workers seen in the last 24 h; older rows are past processes (worker ids change per run). */
export async function listWorkers(): Promise<WorkerHeartbeat[]> {
  const supabase = await reader();
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabase
    .from('worker_heartbeats')
    .select('worker_id, status, version, job_types, active_model_profile, last_seen_at')
    .gte('last_seen_at', since)
    .order('last_seen_at', { ascending: false });
  if (error !== null) throw new JobDataError('workers', error.code);
  return z.array(workerSchema).parse(data);
}
