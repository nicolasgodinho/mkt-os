-- Increment 8 — Drive sync minimum (docs/13): connection and file registry, manual and periodic
-- sync, index/re-index hooks, failure states.
--
-- * A connection names a client's Google Drive folder and a server-side credential reference;
--   secrets never enter the database (docs/05 §5).
-- * Physical bytes stay in Drive; the database keeps file semantics and Drive identifiers
--   (docs/02 Asset/Files, docs/09 "Drive connector").
-- * A sync is a `drive.sync` job: the worker lists the folder tree and returns a snapshot that the
--   database applies in the job's completion transaction (ADR 0003 pattern, ADR 0004), so a
--   redelivery never applies twice (docs/11 invariant 6). Completing schedules the next periodic
--   sync through the queue's run_after.
-- * New or changed files are left `pending` for indexing: the hook later indexing consumes.
-- Contract: tests/acceptance/increment-8/README.md.

create type public.integration_status as enum ('active', 'paused');
create type public.file_sync_status as enum ('synced', 'removed');
create type public.file_index_status as enum ('pending', 'indexing', 'indexed', 'failed', 'skipped');

create table public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id),
  client_id uuid not null,
  provider text not null check (provider in ('google_drive')),
  status public.integration_status not null default 'active',
  root_folder_id text not null check (root_folder_id ~ '^[A-Za-z0-9_-]{10,200}$'),
  -- Name of a credential the worker resolves from its own environment; never the secret itself.
  credential_ref text not null default 'default' check (credential_ref ~ '^[a-z0-9_]{1,40}$'),
  scopes text[] not null default array['https://www.googleapis.com/auth/drive.readonly'],
  sync_interval_minutes integer not null default 60 check (sync_interval_minutes between 15 and 1440),
  last_success_at timestamptz,
  created_by uuid not null references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (client_id, provider),
  -- A folder feeds exactly one client: the same folder under two clients would mix their files.
  unique (provider, root_folder_id),
  unique (id, client_id),
  foreign key (client_id, workspace_id) references public.clients (id, workspace_id)
);

create table public.file_records (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id),
  client_id uuid not null,
  connection_id uuid not null,
  drive_file_id text not null check (drive_file_id ~ '^[A-Za-z0-9_-]{1,200}$'),
  name text not null check (char_length(name) between 1 and 500),
  mime_type text not null check (char_length(mime_type) between 1 and 200),
  drive_revision text not null check (char_length(drive_revision) between 1 and 200),
  modified_at timestamptz,
  size_bytes bigint check (size_bytes >= 0),
  md5_checksum text check (md5_checksum ~ '^[a-f0-9]{32}$'),
  sync_status public.file_sync_status not null default 'synced',
  index_status public.file_index_status not null default 'pending',
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connection_id, drive_file_id),
  foreign key (connection_id, client_id) references public.integration_connections (id, client_id)
);
-- Finds the sync jobs of one connection without scanning the whole queue.
create index jobs_drive_sync_connection_idx on public.jobs ((input ->> 'connection_id'))
  where type = 'drive.sync';
create index file_records_client_idx on public.file_records (client_id, sync_status);
create index file_records_index_pending_idx on public.file_records (index_status)
  where index_status = 'pending';

-- Queues (or brings forward, or re-queues) the single sync job of a connection.
create function app.queue_drive_sync(p_connection public.integration_connections, p_run_after timestamptz)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_job_id uuid;
begin
  -- Serialize per connection so two requests never open two jobs.
  perform pg_advisory_xact_lock(hashtextextended('drive.sync:' || p_connection.id::text, 0));
  select j.id into v_job_id
    from public.jobs j
   where j.type = 'drive.sync' and j.input ->> 'connection_id' = p_connection.id::text
     and j.status in ('queued', 'retry_wait', 'running')
   order by j.created_at desc
   limit 1;
  if v_job_id is not null then
    update public.jobs j set run_after = least(j.run_after, p_run_after), status = 'queued'
     where j.id = v_job_id and j.status in ('queued', 'retry_wait');
    return v_job_id;
  end if;
  -- A sync that ended without a result is retried as the same unit of work (attempts kept):
  -- failure states stay on one job instead of piling up.
  select j.id into v_job_id
    from public.jobs j
   where j.type = 'drive.sync' and j.input ->> 'connection_id' = p_connection.id::text
     and j.status in ('failed', 'dead_letter', 'canceled')
   order by j.created_at desc, j.id
   limit 1;
  if v_job_id is not null and p_run_after <= now() and app.requeue_if_finished(v_job_id) then
    return v_job_id;
  end if;
  v_job_id := app.enqueue_job(
    p_connection.workspace_id, p_connection.client_id, 'drive.sync', 1,
    'drive.sync.v1:' || p_connection.id::text || ':' || gen_random_uuid()::text,
    jsonb_build_object('connection_id', p_connection.id),
    60, 3, null, 'drive.sync/1', null, auth.uid()
  );
  update public.jobs set run_after = p_run_after where id = v_job_id;
  return v_job_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Connection API (integration.manage)
-- -----------------------------------------------------------------------------
create function public.connect_drive_folder(
  p_client_id uuid,
  p_root_folder_id text,
  p_credential_ref text default 'default',
  p_sync_interval_minutes integer default 60
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_workspace_id uuid := app.require_item_capability(p_client_id, 'integration.manage');
  v_connection public.integration_connections;
begin
  if p_root_folder_id is null or p_root_folder_id !~ '^[A-Za-z0-9_-]{10,200}$' then
    raise exception 'invalid drive folder id' using errcode = '22023';
  end if;
  if p_credential_ref is null or p_credential_ref !~ '^[a-z0-9_]{1,40}$' then
    raise exception 'invalid credential reference' using errcode = '22023';
  end if;
  if p_sync_interval_minutes is null or p_sync_interval_minutes not between 15 and 1440 then
    raise exception 'invalid sync interval' using errcode = '22023';
  end if;
  perform 1 from public.clients c where c.id = p_client_id for update;
  if exists (select 1 from public.integration_connections i
              where i.client_id = p_client_id and i.provider = 'google_drive') then
    raise exception 'this client already has a drive connection' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('drive.folder:' || p_root_folder_id, 0));
  if exists (select 1 from public.integration_connections i
              where i.provider = 'google_drive' and i.root_folder_id = p_root_folder_id) then
    raise exception 'this folder is already connected to a client' using errcode = '22023';
  end if;

  insert into public.integration_connections (workspace_id, client_id, provider, root_folder_id,
                                              credential_ref, sync_interval_minutes, created_by)
  values (v_workspace_id, p_client_id, 'google_drive', p_root_folder_id, p_credential_ref,
          p_sync_interval_minutes, v_uid)
  returning * into v_connection;
  perform app.queue_drive_sync(v_connection, now());
  perform app.audit(v_workspace_id, p_client_id, 'drive.connected', 'integration_connection',
                    v_connection.id, null,
                    jsonb_build_object('root_folder_id', p_root_folder_id,
                                       'credential_ref', p_credential_ref));
  return v_connection.id;
end;
$$;

create function public.set_drive_connection_status(p_connection_id uuid, p_status text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_connection public.integration_connections;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_connection from public.integration_connections i where i.id = p_connection_id;
  v_workspace_id := app.require_item_capability(v_connection.client_id, 'integration.manage');
  if p_status is null or p_status not in ('active', 'paused') then
    raise exception 'unknown connection status' using errcode = '22023';
  end if;
  select * into v_connection from public.integration_connections i
   where i.id = p_connection_id for update;
  if v_connection.status::text = p_status then
    return;
  end if;
  update public.integration_connections
     set status = p_status::public.integration_status, updated_at = now()
   where id = p_connection_id
  returning * into v_connection;
  if p_status = 'paused' then
    update public.jobs j set status = 'canceled', finished_at = now()
     where j.type = 'drive.sync' and j.input ->> 'connection_id' = p_connection_id::text
       and j.status in ('queued', 'retry_wait');
  else
    perform app.queue_drive_sync(v_connection, now());
  end if;
  perform app.audit(v_workspace_id, v_connection.client_id,
                    case p_status when 'paused' then 'drive.paused' else 'drive.resumed' end,
                    'integration_connection', p_connection_id, null,
                    jsonb_build_object('status', p_status));
end;
$$;

create function public.request_drive_sync(p_connection_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_connection public.integration_connections;
  v_workspace_id uuid;
  v_job_id uuid;
begin
  perform app.require_uid();
  select * into v_connection from public.integration_connections i where i.id = p_connection_id;
  v_workspace_id := app.require_item_capability(v_connection.client_id, 'integration.manage');
  select * into v_connection from public.integration_connections i
   where i.id = p_connection_id for update;
  if v_connection.status = 'paused' then
    raise exception 'this drive connection is paused' using errcode = '22023';
  end if;
  v_job_id := app.queue_drive_sync(v_connection, now());
  perform app.audit(v_workspace_id, v_connection.client_id, 'drive.sync_requested',
                    'integration_connection', p_connection_id, null,
                    jsonb_build_object('job_id', v_job_id));
  return v_job_id;
end;
$$;

-- Re-index hook: the file goes back to `pending` for the indexing pipeline.
create function public.request_file_reindex(p_file_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_file public.file_records;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_file from public.file_records f where f.id = p_file_id;
  v_workspace_id := app.require_item_capability(v_file.client_id, 'integration.manage');
  select * into v_file from public.file_records f where f.id = p_file_id for update;
  if v_file.sync_status = 'removed' then
    raise exception 'removed files cannot be indexed' using errcode = '22023';
  end if;
  update public.file_records set index_status = 'pending', updated_at = now() where id = p_file_id;
  perform app.audit(v_workspace_id, v_file.client_id, 'file.reindex_requested', 'file_record',
                    p_file_id, jsonb_build_object('index_status', v_file.index_status),
                    jsonb_build_object('index_status', 'pending'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Worker API (ADR 0004): scoped to the leased job, never to a tenant id
-- -----------------------------------------------------------------------------
create function worker.drive_sync_for_job(p_job_id uuid, p_worker_id text, p_attempt integer)
returns table (connection_id uuid, root_folder_id text, credential_ref text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform worker.assert_worker_id(p_worker_id);
  return query
  select i.id, i.root_folder_id, i.credential_ref
    from public.jobs j
    join public.integration_connections i
      on i.id = (j.input ->> 'connection_id')::uuid and i.client_id = j.client_id
   where j.id = p_job_id
     and j.status = 'running'
     and j.lease_owner = p_worker_id
     and j.attempts = p_attempt
     and j.type = 'drive.sync'
     and j.schema_version = 1
     -- A paused connection is never listed, even by a job that was already running or retrying.
     and i.status = 'active';
end;
$$;

create function worker.complete_drive_sync(
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
  v_lease record := worker.lease_for_completion(p_job_id, p_worker_id, p_attempt, 'drive.sync');
  v_job public.jobs := v_lease.job;
  v_connection public.integration_connections;
  v_item jsonb;
  v_seen text[] := '{}';
  v_added integer := 0;
  v_changed integer := 0;
  v_removed integer := 0;
begin
  if v_lease.outcome <> 'ok' then
    return v_lease.outcome;
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or jsonb_typeof(p_result -> 'files') is distinct from 'array'
     or jsonb_array_length(p_result -> 'files') > 5000 then
    raise exception 'invalid drive sync result' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(p_result -> 'files') loop
    if jsonb_typeof(v_item) <> 'object'
       or jsonb_typeof(v_item -> 'drive_file_id') is distinct from 'string'
       or (v_item ->> 'drive_file_id') !~ '^[A-Za-z0-9_-]{1,200}$'
       or jsonb_typeof(v_item -> 'name') is distinct from 'string'
       or char_length(v_item ->> 'name') not between 1 and 500
       or jsonb_typeof(v_item -> 'mime_type') is distinct from 'string'
       or char_length(v_item ->> 'mime_type') not between 1 and 200
       or jsonb_typeof(v_item -> 'revision') is distinct from 'string'
       or char_length(v_item ->> 'revision') not between 1 and 200
       or (v_item ? 'size_bytes' and (jsonb_typeof(v_item -> 'size_bytes') <> 'number'
                                      or (v_item ->> 'size_bytes') !~ '^[0-9]{1,18}$'))
       or (v_item ? 'md5_checksum' and coalesce(v_item ->> 'md5_checksum', '') !~ '^[a-f0-9]{32}$')
       or (v_item ? 'modified_at' and coalesce(v_item ->> 'modified_at', '')
             !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$')
       or (v_item ->> 'drive_file_id') = any (v_seen) then
      raise exception 'invalid drive sync result' using errcode = '22023';
    end if;
    v_seen := v_seen || (v_item ->> 'drive_file_id');
  end loop;

  select * into v_connection from public.integration_connections i
   where i.id = (v_job.input ->> 'connection_id')::uuid and i.client_id = v_job.client_id
     for update;

  for v_item in select value from jsonb_array_elements(p_result -> 'files') loop
    update public.file_records f
       set name = v_item ->> 'name',
           mime_type = v_item ->> 'mime_type',
           index_status = case
             when f.sync_status = 'removed' or f.drive_revision <> v_item ->> 'revision'
             then 'pending'::public.file_index_status else f.index_status end,
           drive_revision = v_item ->> 'revision',
           modified_at = (v_item ->> 'modified_at')::timestamptz,
           size_bytes = (v_item ->> 'size_bytes')::bigint,
           md5_checksum = v_item ->> 'md5_checksum',
           sync_status = 'synced',
           last_seen_at = now(),
           updated_at = now()
     where f.connection_id = v_connection.id and f.drive_file_id = v_item ->> 'drive_file_id'
       and (f.sync_status = 'removed' or f.drive_revision <> v_item ->> 'revision'
            or f.name <> v_item ->> 'name' or f.mime_type <> v_item ->> 'mime_type');
    if found then
      v_changed := v_changed + 1;
    elsif not exists (select 1 from public.file_records f
                       where f.connection_id = v_connection.id
                         and f.drive_file_id = v_item ->> 'drive_file_id') then
      insert into public.file_records (workspace_id, client_id, connection_id, drive_file_id, name,
                                       mime_type, drive_revision, modified_at, size_bytes,
                                       md5_checksum)
      values (v_connection.workspace_id, v_connection.client_id, v_connection.id,
              v_item ->> 'drive_file_id', v_item ->> 'name', v_item ->> 'mime_type',
              v_item ->> 'revision', (v_item ->> 'modified_at')::timestamptz,
              (v_item ->> 'size_bytes')::bigint, v_item ->> 'md5_checksum');
      v_added := v_added + 1;
    end if;
  end loop;

  -- The snapshot is the whole folder tree: anything not in it was removed or moved out.
  update public.file_records f
     set sync_status = 'removed', index_status = 'skipped', updated_at = now()
   where f.connection_id = v_connection.id and f.sync_status = 'synced'
     and not (f.drive_file_id = any (v_seen));
  get diagnostics v_removed = row_count;

  update public.integration_connections set last_success_at = now(), updated_at = now()
   where id = v_connection.id;
  perform worker.finish_job(v_job.id, jsonb_build_object(
    'files', jsonb_array_length(p_result -> 'files'), 'added', v_added, 'changed', v_changed,
    'removed', v_removed));
  if v_connection.status = 'active' then
    perform app.queue_drive_sync(v_connection,
                                 now() + make_interval(mins => v_connection.sync_interval_minutes));
  end if;
  return 'completed';
end;
$$;

-- The job center's generic retry would bypass the one-open-sync rule and pausing: Drive syncs are
-- retried through request_drive_sync (the Drive page) instead. Same function as Increment 3,
-- plus that refusal.
create or replace function public.retry_job(p_job_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_job public.jobs := app.require_manageable_job(p_job_id);
begin
  if v_job.type = 'drive.sync' then
    raise exception 'drive syncs are retried from the drive page' using errcode = '22023';
  end if;
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

-- -----------------------------------------------------------------------------
-- RLS and privileges
-- -----------------------------------------------------------------------------
alter table public.integration_connections enable row level security;
alter table public.file_records enable row level security;

create policy integration_connections_select_internal on public.integration_connections
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy file_records_select_internal on public.file_records
  for select to authenticated using (app.has_internal_client_access(client_id));

revoke all on table public.integration_connections, public.file_records from anon, authenticated;
grant select on table public.integration_connections, public.file_records to authenticated;

revoke execute on function app.queue_drive_sync(public.integration_connections, timestamptz)
  from public, anon, authenticated;

revoke execute on function
  public.connect_drive_folder(uuid, text, text, integer),
  public.set_drive_connection_status(uuid, text),
  public.request_drive_sync(uuid),
  public.request_file_reindex(uuid)
from public, anon;
grant execute on function
  public.connect_drive_folder(uuid, text, text, integer),
  public.set_drive_connection_status(uuid, text),
  public.request_drive_sync(uuid),
  public.request_file_reindex(uuid)
to authenticated;

revoke execute on function
  worker.drive_sync_for_job(uuid, text, integer),
  worker.complete_drive_sync(uuid, text, integer, jsonb)
from public, anon, authenticated;
grant execute on function
  worker.drive_sync_for_job(uuid, text, integer),
  worker.complete_drive_sync(uuid, text, integer, jsonb)
to jmos_worker;
