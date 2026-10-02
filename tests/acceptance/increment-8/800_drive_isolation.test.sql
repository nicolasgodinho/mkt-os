-- Increment 8 / Who sees the Drive registry, tenant isolation, no direct writes, worker boundary
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-8/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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

-- A1's first sync, then B1's: one open sync job at a time keeps the claims deterministic.
select set_config('acc.job_a1', (select id::text from worker.claim_job('acc-worker', array['drive.sync.v1'], 300)), true);
select worker.complete_drive_sync(current_setting('acc.job_a1')::uuid, 'acc-worker', 1,
  '{"files": [{"drive_file_id": "fileA1doc0001", "name": "Briefing A1.docx", "mime_type": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "revision": "r1"}]}'::jsonb);
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_config('acc.conn_b1', public.connect_drive_folder(
  'b1000000-0000-4000-8000-0000000000b1', '1BbCdEfGhIjKlMnOpQrStUvWxYz_b1')::text, true);
reset role;
select set_config('acc.job_b1', (select id::text from worker.claim_job('acc-worker', array['drive.sync.v1'], 300)), true);
select worker.complete_drive_sync(current_setting('acc.job_b1')::uuid, 'acc-worker', 1,
  '{"files": [{"drive_file_id": "fileB1secret1", "name": "Contrato B1.pdf", "mime_type": "application/pdf", "revision": "r1"}]}'::jsonb);
select set_config('acc.file_a1', (select id::text from public.file_records where drive_file_id = 'fileA1doc0001'), true);

-- ===========================================================================
-- Who sees the Drive registry (docs/05, docs/11 invariant 9)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_eq($$ select id from public.integration_connections $$,
  $$ select current_setting('acc.conn_a1')::uuid $$,
  'internal staff with client access see the client''s Drive connection');
select set_eq($$ select drive_file_id from public.file_records $$,
  $$ values ('fileA1doc0001') $$,
  'internal staff see the client''s file records');
select throws_ok($$ select public.connect_drive_folder('a2000000-0000-4000-8000-0000000000a2', '1AbCdEfGhIjKlMnOpQrStUvWxYz_a2') $$,
  '42501', 'permission denied', 'connecting a folder needs integration.manage');
select throws_ok($$ select public.request_drive_sync(current_setting('acc.conn_a1')::uuid) $$,
  '42501', 'permission denied', 'requesting a sync needs integration.manage');
select throws_ok($$ select public.set_drive_connection_status(current_setting('acc.conn_a1')::uuid, 'paused') $$,
  '42501', 'permission denied', 'pausing a connection needs integration.manage');
select throws_ok($$ select public.request_file_reindex(current_setting('acc.file_a1')::uuid) $$,
  '42501', 'permission denied', 'requesting a re-index needs integration.manage');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.integration_connections union all select 1 from public.file_records $$,
  'client members see no Drive registry in v0.1');
select throws_ok($$ select public.request_drive_sync(current_setting('acc.conn_a1')::uuid) $$,
  'P0002', 'not found', 'a client member cannot trigger a sync');
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.integration_connections $$,
  $$ select current_setting('acc.conn_b1')::uuid $$,
  'admin B sees only workspace B connections');
select is_empty($$ select 1 from public.file_records where client_id <> 'b1000000-0000-4000-8000-0000000000b1' $$,
  'admin B sees no file of workspace A');
select throws_ok($$ select public.connect_drive_folder('a2000000-0000-4000-8000-0000000000a2', '1AbCdEfGhIjKlMnOpQrStUvWxYz_a2') $$,
  'P0002', 'not found', 'admin B cannot connect a workspace A client');
select throws_ok($$ select public.request_drive_sync(current_setting('acc.conn_a1')::uuid) $$,
  'P0002', 'not found', 'admin B cannot sync a workspace A connection');
select throws_ok($$ select public.request_file_reindex(current_setting('acc.file_a1')::uuid) $$,
  'P0002', 'not found', 'admin B cannot re-index a workspace A file');
reset role;

-- No direct writes ---------------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ update public.integration_connections set status = 'paused' $$,
  '42501', null, 'connections cannot be updated directly, even by an admin');
select throws_ok($$ update public.file_records set index_status = 'indexed' $$,
  '42501', null, 'file records cannot be updated directly');
reset role;
select pg_temp.login_anon();
select throws_ok($$ select 1 from public.file_records $$, '42501', null, 'anon reads nothing');
reset role;
select is_empty(
  $$ select t from unnest(array['integration_connections', 'file_records']) t
      where has_table_privilege('authenticated', 'public.' || t, 'INSERT, UPDATE, DELETE, TRUNCATE')
         or has_table_privilege('anon', 'public.' || t, 'SELECT')
         or not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) $$,
  'Drive tables have RLS, no API write privileges and no anon access');

-- Worker boundary (ADR 0001 rule, extended by this increment) ---------------------------
select is_empty(
  $$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'worker' and p.proname in ('drive_sync_for_job', 'complete_drive_sync')
        and (p.proargnames && array['p_workspace_id', 'p_client_id', 'p_connection_id']
             or has_function_privilege('authenticated', p.oid, 'EXECUTE')
             or has_function_privilege('anon', p.oid, 'EXECUTE')) $$,
  'the Drive worker functions take no tenant id and are not callable by API roles');

select * from finish();
rollback;
