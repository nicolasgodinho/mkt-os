-- Increment 8 / The sync job: snapshots, re-index hook, fencing and failure states
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-8/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.login_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end;
$$;

create function pg_temp.make_user(p_id uuid, p_email text) returns void language plpgsql as $$
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_email, now(), now());
  insert into public.users (id, display_name) values (p_id, p_email) on conflict (id) do nothing;
end;
$$;

-- Open sync jobs of a connection (queued, waiting to retry or running).
create function pg_temp.open_syncs(p_connection uuid) returns integer language sql as $$
  select count(*)::integer from public.jobs
   where type = 'drive.sync' and (input ->> 'connection_id')::uuid = p_connection
     and status in ('queued', 'retry_wait', 'running');
$$;

-- ---------------------------------------------------------------------------
-- Fixture (see README): Workspace A {A1, A2}, Workspace B {B1}
-- ---------------------------------------------------------------------------
select pg_temp.make_user(id, email) from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'a_admin@acc.test'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test')
) as u(id, email);

insert into public.workspaces (id, name, slug) values
  ('a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Workspace A', 'acc-ws-a'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'Secret Workspace B', 'acc-ws-b');

insert into public.clients (id, workspace_id, name, slug) values
  ('a1000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Client A1', 'acc-client-a1'),
  ('a2000000-0000-4000-8000-0000000000a2', 'a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Client A2', 'acc-client-a2'),
  ('b1000000-0000-4000-8000-0000000000b1', 'b0000000-0000-4000-8000-00000000bbbb', 'Secret Client B1', 'acc-client-b1');

insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status) values
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active');

-- A1 is connected by the workspace admin; the worker side runs as the privileged owner, exactly
-- like `jmos_worker` calling the `worker.*` API.
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.conn_a1', public.connect_drive_folder(
  'a1000000-0000-4000-8000-0000000000a1', '1AbCdEfGhIjKlMnOpQrStUvWxYz_a1')::text, true);
reset role;

-- ===========================================================================
-- The sync job (docs/09 "Drive connector", docs/11 invariant 6)
-- ===========================================================================
select set_config('acc.job1', (select id::text from public.jobs where type = 'drive.sync'
  and (input ->> 'connection_id')::uuid = current_setting('acc.conn_a1')::uuid), true);
select is_empty($$ select 1 from worker.drive_sync_for_job(current_setting('acc.job1')::uuid, 'acc-worker', 1) $$,
  'a sync job that is not leased exposes nothing');
select is((select id from worker.claim_job('acc-worker', array['drive.sync.v1'], 300)),
  current_setting('acc.job1')::uuid, 'the worker leases the sync job');
select results_eq(
  $$ select connection_id, root_folder_id, credential_ref
       from worker.drive_sync_for_job(current_setting('acc.job1')::uuid, 'acc-worker', 1) $$,
  $$ values (current_setting('acc.conn_a1')::uuid, '1AbCdEfGhIjKlMnOpQrStUvWxYz_a1', 'default') $$,
  'under its lease the worker gets the folder and the credential reference');
select is_empty($$ select 1 from worker.drive_sync_for_job(current_setting('acc.job1')::uuid, 'other-worker', 1) $$,
  'another worker gets nothing');

-- First snapshot ---------------------------------------------------------------------------
select is(worker.complete_drive_sync(current_setting('acc.job1')::uuid, 'acc-worker', 1,
  '{"files": [
     {"drive_file_id": "fileA1doc0001", "name": "Briefing.docx", "mime_type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "revision": "r1"},
     {"drive_file_id": "fileA1img0002", "name": "Logo.png", "mime_type": "image/png", "revision": "r1", "size_bytes": 2048},
     {"drive_file_id": "fileA1pdf0003", "name": "Manual.pdf", "mime_type": "application/pdf", "revision": "r1"}]}'::jsonb),
  'completed', 'the worker completes the snapshot');
select set_eq(
  $$ select drive_file_id, name, sync_status::text, index_status::text, drive_revision
       from public.file_records where connection_id = current_setting('acc.conn_a1')::uuid $$,
  $$ values ('fileA1doc0001', 'Briefing.docx', 'synced', 'pending', 'r1'),
            ('fileA1img0002', 'Logo.png', 'synced', 'pending', 'r1'),
            ('fileA1pdf0003', 'Manual.pdf', 'synced', 'pending', 'r1') $$,
  'new files are registered as synced and waiting for indexing');
select is((select count(*)::integer from public.file_records
            where connection_id = current_setting('acc.conn_a1')::uuid
              and client_id = 'a1000000-0000-4000-8000-0000000000a1'), 3,
  'file records belong to the connection''s client');
select isnt((select last_success_at from public.integration_connections where id = current_setting('acc.conn_a1')::uuid),
  null, 'a successful sync is recorded on the connection');
select results_eq(
  $$ select count(*)::integer, min(run_after) from public.jobs
      where type = 'drive.sync' and status = 'queued'
        and (input ->> 'connection_id')::uuid = current_setting('acc.conn_a1')::uuid $$,
  $$ values (1, now() + interval '60 minutes') $$,
  'completing schedules the next periodic sync after the connection interval');
select is(worker.complete_drive_sync(current_setting('acc.job1')::uuid, 'acc-worker', 1,
  '{"files": [{"drive_file_id": "fileA1extra099", "name": "Duplicado", "mime_type": "text/plain", "revision": "r1"}]}'::jsonb),
  'duplicate', 'a redelivered completion is a duplicate');
select is((select count(*)::integer from public.file_records where connection_id = current_setting('acc.conn_a1')::uuid), 3,
  'a duplicate completion writes nothing');

-- Second snapshot: a manual sync brings the next run forward --------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.job2', public.request_drive_sync(current_setting('acc.conn_a1')::uuid)::text, true);
reset role;
select is((select id from worker.claim_job('acc-worker', array['drive.sync.v1'], 300)),
  current_setting('acc.job2')::uuid, 'a manual sync runs the scheduled job now');
select throws_ok($$ select worker.complete_drive_sync(current_setting('acc.job2')::uuid, 'acc-worker', 1, '{"files": "todos"}'::jsonb) $$,
  '22023', 'invalid drive sync result', 'a malformed result is refused');
select throws_ok($$ select worker.complete_drive_sync(current_setting('acc.job2')::uuid, 'acc-worker', 1,
  '{"files": [{"name": "sem id", "mime_type": "text/plain", "revision": "r1"}]}'::jsonb) $$,
  '22023', 'invalid drive sync result', 'every file needs a Drive id');
select is(worker.complete_drive_sync(current_setting('acc.job2')::uuid, 'acc-worker', 1,
  '{"files": [
     {"drive_file_id": "fileA1doc0001", "name": "Briefing.docx", "mime_type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "revision": "r1"},
     {"drive_file_id": "fileA1img0002", "name": "Logo novo.png", "mime_type": "image/png", "revision": "r2"}]}'::jsonb),
  'completed', 'the second snapshot completes');
select set_eq(
  $$ select drive_file_id, name, sync_status::text, index_status::text, drive_revision
       from public.file_records where connection_id = current_setting('acc.conn_a1')::uuid $$,
  $$ values ('fileA1doc0001', 'Briefing.docx', 'synced', 'pending', 'r1'),
            ('fileA1img0002', 'Logo novo.png', 'synced', 'pending', 'r2'),
            ('fileA1pdf0003', 'Manual.pdf', 'removed', 'skipped', 'r1') $$,
  'a new revision is indexed again; a file missing from the snapshot is marked removed');

-- Re-index hook ----------------------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.request_file_reindex((select id from public.file_records where drive_file_id = 'fileA1pdf0003')) $$,
  '22023', 'removed files cannot be indexed', 'a removed file cannot be re-indexed');
select public.request_file_reindex((select id from public.file_records where drive_file_id = 'fileA1doc0001'));
select is((select index_status::text from public.file_records where drive_file_id = 'fileA1doc0001'), 'pending',
  're-indexing puts the file back in the indexing queue state');
select set_config('acc.job3', public.request_drive_sync(current_setting('acc.conn_a1')::uuid)::text, true);
reset role;

-- Fencing and failure states ---------------------------------------------------------------
select 1 from worker.claim_job('worker-a', array['drive.sync.v1'], 300);
update public.jobs set lease_until = now() - interval '1 second' where id = current_setting('acc.job3')::uuid;
select 1 from worker.claim_job('worker-b', array['drive.sync.v1'], 300);
select is(worker.complete_drive_sync(current_setting('acc.job3')::uuid, 'worker-a', 1, '{"files": []}'::jsonb),
  'lease_lost', 'a worker whose lease expired cannot complete the sync');
select is((select count(*)::integer from public.file_records
            where connection_id = current_setting('acc.conn_a1')::uuid and sync_status = 'synced'), 2,
  'a fenced-out completion changes nothing');
select is(worker.fail_job(current_setting('acc.job3')::uuid, 'worker-b', 2,
  '{"code": "drive_auth_failed"}'::jsonb, false), 'failed', 'a permanent Drive error fails the job');
select results_eq(
  $$ select j.status::text, j.last_error ->> 'code', pg_temp.open_syncs(current_setting('acc.conn_a1')::uuid)
       from public.jobs j where j.id = current_setting('acc.job3')::uuid $$,
  $$ values ('failed', 'drive_auth_failed', 0) $$,
  'the failure state and its code stay on the sync job; nothing else is scheduled');
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select is(public.request_drive_sync(current_setting('acc.conn_a1')::uuid), current_setting('acc.job3')::uuid,
  'a manual sync after a failure retries the same job');
reset role;
select is((select status::text from public.jobs where id = current_setting('acc.job3')::uuid), 'queued',
  'the failed sync is queued again');

-- A paused connection keeps the last result but schedules nothing --------------------------
select 1 from worker.claim_job('acc-worker', array['drive.sync.v1'], 300);
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.set_drive_connection_status(current_setting('acc.conn_a1')::uuid, 'paused');
reset role;
select is(worker.complete_drive_sync(current_setting('acc.job3')::uuid, 'acc-worker',
  (select attempts from public.jobs where id = current_setting('acc.job3')::uuid),
  '{"files": [
     {"drive_file_id": "fileA1doc0001", "name": "Briefing.docx", "mime_type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "revision": "r1"},
     {"drive_file_id": "fileA1img0002", "name": "Logo novo.png", "mime_type": "image/png", "revision": "r2"},
     {"drive_file_id": "fileA1pdf0003", "name": "Manual.pdf", "mime_type": "application/pdf", "revision": "r1"}]}'::jsonb),
  'completed', 'a sync that was running when the connection paused still completes');
select results_eq(
  $$ select (select sync_status::text || '/' || index_status::text from public.file_records where drive_file_id = 'fileA1pdf0003'),
            pg_temp.open_syncs(current_setting('acc.conn_a1')::uuid) $$,
  $$ values ('synced/pending', 0) $$,
  'a file that comes back is synced again; a paused connection schedules no next sync');

select * from finish();
rollback;
