-- Increment 3 — Job center (docs/13): request allow-listed system jobs, cancel, retry and a
-- per-workspace status summary, on top of the Increment 0 queue (ADR 0001).
--
-- * Job center actions require `workspace.manage` (no new capability).
-- * Jobs stay read-only for API roles; every change goes through these functions or `worker.*`.
-- * Retry never resets `attempts`: the attempt number is the fencing token, so a stale worker
--   from an earlier attempt can never complete or fail the retried job.
-- Contract: tests/acceptance/increment-3/README.md.

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------
-- A job is a target for the caller exactly when the `jobs_select_internal` policy shows it.
create function app.can_see_job(p_job public.jobs)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
           when p_job.id is null then false
           when p_job.client_id is null then app.has_internal_workspace_access(p_job.workspace_id)
           else app.has_internal_client_access(p_job.client_id)
         end;
$$;

-- Locks a job the caller can manage, or raises P0002 (not visible) / 42501 (no workspace.manage).
create function app.require_manageable_job(p_job_id uuid)
returns public.jobs
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_job public.jobs;
begin
  select * into v_job from public.jobs j where j.id = p_job_id;
  if not app.can_see_job(v_job) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not ('workspace.manage' = any (app.workspace_capabilities_of(v_uid, v_job.workspace_id))) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select * into v_job from public.jobs j where j.id = p_job_id for update;
  return v_job;
end;
$$;

-- -----------------------------------------------------------------------------
-- Database API
-- -----------------------------------------------------------------------------
create function public.request_system_job(
  p_workspace_id uuid,
  p_type text,
  p_idempotency_key text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_key text := btrim(p_idempotency_key);
  v_model_profile text;
  v_pipeline_version text;
  v_existed boolean;
  v_job_id uuid;
begin
  if not exists (
    select 1
      from public.workspace_memberships m
     where m.workspace_id = p_workspace_id
       and m.user_id = v_uid
       and m.status = 'active'
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not ('workspace.manage' = any (app.workspace_capabilities_of(v_uid, p_workspace_id))) then
    raise exception 'permission denied' using errcode = '42501';
  end if;

  -- Allow-list: system jobs only. Domain jobs are enqueued by their own capability-checked
  -- functions. Profiles and pipeline versions are decided here, never by the caller.
  case p_type
    when 'system.healthcheck' then
      v_model_profile := null;
      v_pipeline_version := 'system.healthcheck/1';
    when 'ai.model_check' then
      v_model_profile := 'reasoning';
      v_pipeline_version := 'ai.model_check/1';
    else
      raise exception 'job type cannot be requested' using errcode = '22023';
  end case;
  if v_key is null or v_key = '' or char_length(v_key) > 200 then
    raise exception 'idempotency key is required' using errcode = '22023';
  end if;

  -- Serialize concurrent requests for the same key so the creation is audited exactly once.
  perform pg_advisory_xact_lock(hashtextextended(p_workspace_id::text || ':' || v_key, 0));
  select exists (
    select 1 from public.jobs j where j.workspace_id = p_workspace_id and j.idempotency_key = v_key
  ) into v_existed;

  v_job_id := app.enqueue_job(
    -- Low priority: diagnostics never hold up client-facing work on the single GPU (docs/08 §4).
    p_workspace_id, null, p_type, 1, v_key, '{}'::jsonb, 10, 3, v_model_profile,
    v_pipeline_version, null, v_uid
  );

  if not v_existed then
    perform app.audit(p_workspace_id, null, 'job.requested', 'job', v_job_id, null,
                      jsonb_build_object('type', p_type, 'schema_version', 1));
  end if;
  return v_job_id;
end;
$$;

create function public.cancel_job(p_job_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job public.jobs := app.require_manageable_job(p_job_id);
begin
  if v_job.status not in ('queued', 'retry_wait') then
    raise exception 'only queued or waiting jobs can be canceled' using errcode = '22023';
  end if;

  update public.jobs j
     set status = 'canceled',
         finished_at = now(),
         lease_owner = null,
         lease_until = null
   where j.id = v_job.id;

  perform app.audit(v_job.workspace_id, v_job.client_id, 'job.canceled', 'job', v_job.id,
                    jsonb_build_object('status', v_job.status),
                    jsonb_build_object('status', 'canceled'));
end;
$$;

create function public.retry_job(p_job_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job public.jobs := app.require_manageable_job(p_job_id);
begin
  if v_job.status not in ('failed', 'dead_letter', 'canceled') then
    raise exception 'only failed, dead-lettered or canceled jobs can be retried'
      using errcode = '22023';
  end if;
  if v_job.attempts >= 20 then
    raise exception 'job has no attempts left' using errcode = '22023';
  end if;

  -- Attempts are kept (fencing); the job gets up to three more attempts within the hard cap.
  update public.jobs j
     set status = 'queued',
         run_after = now(),
         finished_at = null,
         max_attempts = greatest(j.max_attempts, least(j.attempts + 3, 20))
   where j.id = v_job.id;

  perform app.audit(v_job.workspace_id, v_job.client_id, 'job.retried', 'job', v_job.id,
                    jsonb_build_object('status', v_job.status, 'attempts', v_job.attempts),
                    jsonb_build_object('status', 'queued'));
end;
$$;

create function public.job_center_summary(p_workspace_id uuid)
returns table (
  queued integer,
  running integer,
  stalled integer,
  retry_wait integer,
  completed integer,
  failed integer,
  dead_letter integer,
  canceled integer,
  last_completed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select count(*) filter (where j.status = 'queued')::integer,
         count(*) filter (where j.status = 'running')::integer,
         count(*) filter (where j.status = 'running' and j.lease_until < now())::integer,
         count(*) filter (where j.status = 'retry_wait')::integer,
         count(*) filter (where j.status = 'completed')::integer,
         count(*) filter (where j.status = 'failed')::integer,
         count(*) filter (where j.status = 'dead_letter')::integer,
         count(*) filter (where j.status = 'canceled')::integer,
         max(j.finished_at) filter (where j.status = 'completed')
    from public.jobs j
   where j.workspace_id = p_workspace_id
  having app.has_internal_workspace_access(p_workspace_id);
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
revoke execute on function
  app.can_see_job(public.jobs),
  app.require_manageable_job(uuid)
from public, anon, authenticated;

revoke execute on function
  public.request_system_job(uuid, text, text),
  public.cancel_job(uuid),
  public.retry_job(uuid),
  public.job_center_summary(uuid)
from public, anon;

grant execute on function
  public.request_system_job(uuid, text, text),
  public.cancel_job(uuid),
  public.retry_job(uuid),
  public.job_center_summary(uuid)
to authenticated;
