-- =============================================================================
-- Increment 0 — Durable job queue and worker heartbeat (Platform bounded context).
-- Spec: docs/04 "AI Job", docs/08 §2 and §5 (job contract, BLOCKER), docs/09 "Scheduler vs Queue",
--       docs/15 "AI worker health".
--
-- Delivery semantics: AT-LEAST-ONCE. A job may run more than once (for example after a worker
-- crash), so correctness relies on:
--   * idempotent enqueue: unique (workspace_id, idempotency_key);
--   * leases fenced by (lease_owner, attempt): a stale worker cannot overwrite a newer attempt;
--   * idempotent completion: completing a completed job is a no-op that returns 'duplicate'.
--
-- Status machine (docs/04; LEASED/RUNNING is the single status `running`):
--   queued -> running -> completed
--   running -> retry_wait -> (due) -> running        retryable failure, attempts left
--   running -> dead_letter                           retries or leases exhausted
--   running -> failed                                permanent (non-retryable) failure
--   queued | retry_wait -> canceled                  reserved for the job center (Increment 3)
--
-- Access:
--   * Jobs are internal-only. Client roles never see jobs (docs/05, docs/11 invariant 9).
--   * The worker connects as `jmos_worker`, which has NO table privileges and may only execute
--     the functions in schema `worker` (not exposed through the Data API). It is not service_role.
--   * `app.enqueue_job` is not callable by API roles yet; Increment 3 adds a capability-checked RPC.
-- =============================================================================

create type public.job_status as enum (
  'queued', 'running', 'retry_wait', 'completed', 'failed', 'dead_letter', 'canceled'
);

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id),
  client_id uuid,
  -- Contract identity: dotted lowercase type + integer schema version (`meeting.extract` v1).
  type text not null
    check (char_length(type) <= 100 and type ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
  schema_version integer not null default 1 check (schema_version between 1 and 1000),
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  -- References to domain records only; never secrets or large blobs (docs/08 §5).
  input jsonb not null default '{}'::jsonb
    check (jsonb_typeof(input) = 'object' and octet_length(input::text) <= 65536),
  priority smallint not null default 50 check (priority between 0 and 100),
  status public.job_status not null default 'queued',
  attempts integer not null default 0,
  max_attempts integer not null default 3 check (max_attempts between 1 and 20),
  run_after timestamptz not null default now(),
  lease_owner text,
  lease_until timestamptz,
  model_profile text check (char_length(model_profile) <= 100),
  pipeline_version text check (char_length(pipeline_version) <= 100),
  trace_id text check (char_length(trace_id) <= 100),
  result jsonb check (result is null or octet_length(result::text) <= 262144),
  last_error jsonb
    check (last_error is null
           or (jsonb_typeof(last_error) = 'object' and octet_length(last_error::text) <= 8192)),
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,

  constraint jobs_client_in_workspace
    foreign key (client_id, workspace_id) references public.clients (id, workspace_id),
  constraint jobs_idempotency_key_unique unique (workspace_id, idempotency_key),
  constraint jobs_attempts_within_max check (attempts between 0 and max_attempts),
  constraint jobs_lease_iff_running
    check ((status = 'running') = (lease_owner is not null and lease_until is not null)),
  constraint jobs_finished_iff_terminal
    check ((status in ('completed', 'failed', 'dead_letter', 'canceled')) = (finished_at is not null)),
  constraint jobs_result_only_when_completed check (result is null or status = 'completed')
);
comment on table public.jobs is
  'Durable background jobs (AI and non-AI). At-least-once delivery; see migration header.';

create index jobs_claimable_idx on public.jobs (priority desc, run_after)
  where status in ('queued', 'retry_wait');
create index jobs_expired_lease_idx on public.jobs (lease_until) where status = 'running';
create index jobs_workspace_status_idx on public.jobs (workspace_id, status);
create index jobs_client_idx on public.jobs (client_id) where client_id is not null;

create trigger jobs_set_updated_at
  before update on public.jobs
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- Worker heartbeat (docs/15 "AI worker health": online/offline, active model profile)
-- -----------------------------------------------------------------------------
create type public.worker_status as enum ('starting', 'idle', 'busy', 'stopping', 'stopped');

create table public.worker_heartbeats (
  worker_id text primary key check (worker_id ~ '^[A-Za-z0-9._:-]{1,100}$'),
  status public.worker_status not null,
  version text not null check (char_length(version) between 1 and 50),
  job_types text[] not null default '{}',
  active_model_profile text check (char_length(active_model_profile) <= 100),
  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
comment on table public.worker_heartbeats is
  'Liveness of AI workers. A worker is offline when last_seen_at is stale.';

-- -----------------------------------------------------------------------------
-- RLS: internal staff only. Client roles and contributors see nothing (fail-closed).
-- -----------------------------------------------------------------------------
alter table public.jobs enable row level security;
alter table public.worker_heartbeats enable row level security;

create policy jobs_select_internal on public.jobs
  for select to authenticated
  using (
    case
      when client_id is null then app.has_internal_workspace_access(workspace_id)
      else app.has_internal_client_access(client_id)
    end
  );

-- Workers are shared agency infrastructure, not tenant data: any internal staff member with
-- workspace-wide access may see worker health.
create function app.is_internal_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.workspace_memberships m
     where m.user_id = (select auth.uid())
       and m.status = 'active'
       and m.role <> 'contributor'
  );
$$;

revoke execute on function app.is_internal_staff() from public, anon, authenticated;
grant execute on function app.is_internal_staff() to authenticated;

create policy worker_heartbeats_select_internal on public.worker_heartbeats
  for select to authenticated
  using (app.is_internal_staff());

revoke all on table public.jobs, public.worker_heartbeats from anon, authenticated;
grant select on table public.jobs, public.worker_heartbeats to authenticated;

-- -----------------------------------------------------------------------------
-- Enqueue (privileged; not exposed to API roles in Increment 0)
-- -----------------------------------------------------------------------------
-- Idempotent: the same (workspace_id, idempotency_key) always returns the same job id.
-- Reusing a key for a different payload is a programming error and raises unique_violation.
create function app.enqueue_job(
  p_workspace_id uuid,
  p_client_id uuid,
  p_type text,
  p_schema_version integer,
  p_idempotency_key text,
  p_input jsonb default '{}'::jsonb,
  p_priority integer default 50,
  p_max_attempts integer default 3,
  p_model_profile text default null,
  p_pipeline_version text default null,
  p_trace_id text default null,
  p_created_by uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job public.jobs;
begin
  insert into public.jobs (
    workspace_id, client_id, type, schema_version, idempotency_key, input, priority,
    max_attempts, model_profile, pipeline_version, trace_id, created_by
  )
  values (
    p_workspace_id, p_client_id, p_type, p_schema_version, p_idempotency_key,
    coalesce(p_input, '{}'::jsonb), p_priority, p_max_attempts, p_model_profile,
    p_pipeline_version, p_trace_id, p_created_by
  )
  on conflict on constraint jobs_idempotency_key_unique do nothing
  returning * into v_job;

  if v_job.id is not null then
    return v_job.id;
  end if;

  select * into v_job
    from public.jobs j
   where j.workspace_id = p_workspace_id
     and j.idempotency_key = p_idempotency_key;

  if v_job.client_id is distinct from p_client_id
     or v_job.type <> p_type
     or v_job.schema_version <> p_schema_version
     or v_job.input <> coalesce(p_input, '{}'::jsonb) then
    raise exception 'idempotency key % was already used for a different job', p_idempotency_key
      using errcode = '23505';
  end if;

  return v_job.id;
end;
$$;

revoke execute on function
  app.enqueue_job(uuid, uuid, text, integer, text, jsonb, integer, integer, text, text, text, uuid)
from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Worker API: the only surface the AI Worker can reach
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'jmos_worker') then
    -- NOLOGIN here; local seed / operators enable LOGIN with a secret password.
    create role jmos_worker nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls;
  end if;
end;
$$;

create schema if not exists worker;
comment on schema worker is
  'Narrow SQL API for the AI Worker (role jmos_worker). Not exposed through the Data API.';
revoke all on schema worker from public;
grant usage on schema worker to jmos_worker;
alter default privileges in schema worker revoke execute on functions from public;

-- Validates identifiers supplied by workers.
create function worker.assert_worker_id(p_worker_id text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_worker_id is null or p_worker_id !~ '^[A-Za-z0-9._:-]{1,100}$' then
    raise exception 'invalid worker id' using errcode = '22023';
  end if;
end;
$$;

-- Leases the next due job whose contract key (`type.vN`) is in p_job_types. Expired leases are
-- recovered first: they return to `queued`, or go to `dead_letter` when attempts are exhausted.
-- Returns zero rows when nothing is due.
create function worker.claim_job(
  p_worker_id text,
  p_job_types text[],
  p_lease_seconds integer default 300
)
returns table (
  id uuid,
  type text,
  schema_version integer,
  workspace_id uuid,
  client_id uuid,
  input jsonb,
  attempt integer,
  max_attempts integer,
  lease_until timestamptz,
  model_profile text,
  pipeline_version text,
  trace_id text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
begin
  perform worker.assert_worker_id(p_worker_id);
  if p_job_types is null or cardinality(p_job_types) = 0 then
    raise exception 'p_job_types must list at least one job contract key' using errcode = '22023';
  end if;
  if p_lease_seconds is null or p_lease_seconds not between 10 and 3600 then
    raise exception 'p_lease_seconds must be between 10 and 3600' using errcode = '22023';
  end if;

  -- 1. Recover leases abandoned by crashed or stalled workers (at-least-once redelivery).
  update public.jobs j
     set status = case when j.attempts >= j.max_attempts
                       then 'dead_letter'::public.job_status
                       else 'queued'::public.job_status end,
         finished_at = case when j.attempts >= j.max_attempts then now() end,
         run_after = now(),
         lease_owner = null,
         lease_until = null,
         last_error = jsonb_build_object(
           'code', 'lease_expired',
           'message', 'lease expired before the job finished',
           'retryable', j.attempts < j.max_attempts,
           'lease_owner', j.lease_owner
         )
   where j.id in (
     select e.id
       from public.jobs e
      where e.status = 'running'
        and e.lease_until < now()
      for update skip locked
   );

  -- 2. Pick the next due job. SKIP LOCKED lets concurrent workers claim different jobs.
  select j.id into v_job_id
    from public.jobs j
   where j.status in ('queued', 'retry_wait')
     and j.run_after <= now()
     and (j.type || '.v' || j.schema_version::text) = any (p_job_types)
   order by j.priority desc, j.run_after, j.created_at
   limit 1
   for update skip locked;

  if v_job_id is null then
    return;
  end if;

  -- 3. Lease it. The incremented attempt number is the fencing token for later writes.
  return query
  update public.jobs j
     set status = 'running',
         attempts = j.attempts + 1,
         lease_owner = p_worker_id,
         lease_until = now() + make_interval(secs => p_lease_seconds),
         started_at = now()
   where j.id = v_job_id
  returning j.id, j.type, j.schema_version, j.workspace_id, j.client_id, j.input, j.attempts,
            j.max_attempts, j.lease_until, j.model_profile, j.pipeline_version, j.trace_id;
end;
$$;

-- Extends the lease of a long-running job. Returns false if the lease is no longer held.
create function worker.extend_lease(
  p_job_id uuid,
  p_worker_id text,
  p_attempt integer,
  p_lease_seconds integer default 300
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform worker.assert_worker_id(p_worker_id);
  if p_lease_seconds is null or p_lease_seconds not between 10 and 3600 then
    raise exception 'p_lease_seconds must be between 10 and 3600' using errcode = '22023';
  end if;

  update public.jobs j
     set lease_until = now() + make_interval(secs => p_lease_seconds)
   where j.id = p_job_id
     and j.status = 'running'
     and j.lease_owner = p_worker_id
     and j.attempts = p_attempt;

  return found;
end;
$$;

-- Records a successful result. Returns:
--   'completed'  the lease was held and the job is now completed;
--   'duplicate'  the job was already completed (redelivery); nothing changed;
--   'lease_lost' the caller no longer holds the lease (reclaimed or finished); nothing changed.
create function worker.complete_job(
  p_job_id uuid,
  p_worker_id text,
  p_attempt integer,
  p_result jsonb
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job public.jobs;
begin
  perform worker.assert_worker_id(p_worker_id);
  if p_result is null or jsonb_typeof(p_result) <> 'object' then
    raise exception 'p_result must be a JSON object' using errcode = '22023';
  end if;

  select * into v_job from public.jobs j where j.id = p_job_id for update;
  if not found then
    raise exception 'job % not found', p_job_id using errcode = 'P0002';
  end if;

  if v_job.status = 'completed' then
    return 'duplicate';
  end if;
  if v_job.status <> 'running'
     or v_job.lease_owner is distinct from p_worker_id
     or v_job.attempts <> p_attempt then
    return 'lease_lost';
  end if;

  update public.jobs j
     set status = 'completed',
         result = p_result,
         last_error = null,
         lease_owner = null,
         lease_until = null,
         finished_at = now()
   where j.id = p_job_id;

  return 'completed';
end;
$$;

-- Records a failure. Retryable failures back off exponentially: 30s * 2^(attempt-1), capped
-- at 1h. Returns 'retry_scheduled', 'dead_letter', 'failed' or 'lease_lost'.
create function worker.fail_job(
  p_job_id uuid,
  p_worker_id text,
  p_attempt integer,
  p_error jsonb,
  p_retryable boolean
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job public.jobs;
begin
  perform worker.assert_worker_id(p_worker_id);
  if p_error is null or jsonb_typeof(p_error) <> 'object' or not (p_error ? 'code') then
    raise exception 'p_error must be a JSON object with a code' using errcode = '22023';
  end if;
  if p_retryable is null then
    raise exception 'p_retryable is required' using errcode = '22023';
  end if;

  select * into v_job from public.jobs j where j.id = p_job_id for update;
  if not found then
    raise exception 'job % not found', p_job_id using errcode = 'P0002';
  end if;

  if v_job.status <> 'running'
     or v_job.lease_owner is distinct from p_worker_id
     or v_job.attempts <> p_attempt then
    return 'lease_lost';
  end if;

  if p_retryable and v_job.attempts < v_job.max_attempts then
    update public.jobs j
       set status = 'retry_wait',
           run_after = now() + least(
             make_interval(secs => 30 * power(2, v_job.attempts - 1)),
             interval '1 hour'
           ),
           last_error = p_error,
           lease_owner = null,
           lease_until = null
     where j.id = p_job_id;
    return 'retry_scheduled';
  end if;

  update public.jobs j
     set status = case when p_retryable then 'dead_letter'::public.job_status
                       else 'failed'::public.job_status end,
         last_error = p_error,
         lease_owner = null,
         lease_until = null,
         finished_at = now()
   where j.id = p_job_id;

  return case when p_retryable then 'dead_letter' else 'failed' end;
end;
$$;

-- Upserts the worker's liveness row. `starting` resets started_at (a new process).
create function worker.heartbeat(
  p_worker_id text,
  p_status public.worker_status,
  p_version text,
  p_job_types text[],
  p_active_model_profile text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform worker.assert_worker_id(p_worker_id);

  insert into public.worker_heartbeats as h (
    worker_id, status, version, job_types, active_model_profile, started_at, last_seen_at
  )
  values (
    p_worker_id, p_status, p_version, coalesce(p_job_types, '{}'), p_active_model_profile,
    now(), now()
  )
  on conflict (worker_id) do update
     set status = excluded.status,
         version = excluded.version,
         job_types = excluded.job_types,
         active_model_profile = excluded.active_model_profile,
         started_at = case when excluded.status = 'starting' then now() else h.started_at end,
         last_seen_at = now();
end;
$$;

revoke execute on all functions in schema worker from public, anon, authenticated;

grant execute on function
  worker.claim_job(text, text[], integer),
  worker.extend_lease(uuid, text, integer, integer),
  worker.complete_job(uuid, text, integer, jsonb),
  worker.fail_job(uuid, text, integer, jsonb, boolean),
  worker.heartbeat(text, public.worker_status, text, text[], text)
to jmos_worker;

-- worker.assert_worker_id is an internal helper called by the functions above (owner context).
