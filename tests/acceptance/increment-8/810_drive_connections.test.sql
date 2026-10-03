-- Increment 8 / Connecting a folder, manual sync, pause and resume
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-8/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

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
-- Connecting a client folder (docs/13 step 3, docs/10 integration_connections)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.conn_a2', public.connect_drive_folder(
  'a2000000-0000-4000-8000-0000000000a2', '1AbCdEfGhIjKlMnOpQrStUvWxYz_a2', 'agency_drive', 30)::text, true);
select results_eq(
  $$ select client_id, provider, status::text, root_folder_id, credential_ref, sync_interval_minutes, last_success_at
       from public.integration_connections where id = current_setting('acc.conn_a2')::uuid $$,
  $$ values ('a2000000-0000-4000-8000-0000000000a2'::uuid, 'google_drive', 'active',
             '1AbCdEfGhIjKlMnOpQrStUvWxYz_a2', 'agency_drive', 30, null::timestamptz) $$,
  'a connection names a folder and a server-side credential, never a secret');
reset role;
select results_eq(
  $$ select client_id, schema_version, status::text, run_after <= now()
       from public.jobs where type = 'drive.sync'
        and (input ->> 'connection_id')::uuid = current_setting('acc.conn_a2')::uuid $$,
  $$ values ('a2000000-0000-4000-8000-0000000000a2'::uuid, 1, 'queued', true) $$,
  'connecting queues the first sync right away, scoped to the client');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.connect_drive_folder('a2000000-0000-4000-8000-0000000000a2', '1AbCdEfGhIjKlMnOpQrStUvWxYz_xx') $$,
  '22023', 'this client already has a drive connection', 'one Drive connection per client');
select throws_ok($$ select public.connect_drive_folder('a1000000-0000-4000-8000-0000000000a1', 'x') $$,
  '22023', 'invalid drive folder id', 'the folder id has the Drive id format');
select throws_ok($$ select public.connect_drive_folder('a1000000-0000-4000-8000-0000000000a1', '1AbCdEfGhIjKlMnOpQrStUvWxYz_zz', 'Prod Secret: abc!') $$,
  '22023', 'invalid credential reference', 'a credential reference is a short name, not a secret');
select throws_ok($$ select public.connect_drive_folder('a1000000-0000-4000-8000-0000000000a1', '1AbCdEfGhIjKlMnOpQrStUvWxYz_zz', 'default', 5) $$,
  '22023', 'invalid sync interval', 'the sync interval stays between 15 minutes and a day');

-- Manual sync never piles up jobs --------------------------------------------------------
select is(public.request_drive_sync(current_setting('acc.conn_a2')::uuid),
  (select id from public.jobs where type = 'drive.sync'
      and (input ->> 'connection_id')::uuid = current_setting('acc.conn_a2')::uuid),
  'requesting a sync while one is open returns the open job');
select is(pg_temp.open_syncs(current_setting('acc.conn_a2')::uuid), 1,
  'a connection has at most one open sync job');

-- Pause and resume -----------------------------------------------------------------------
select public.set_drive_connection_status(current_setting('acc.conn_a2')::uuid, 'paused');
select results_eq(
  $$ select (select status::text from public.integration_connections where id = current_setting('acc.conn_a2')::uuid),
            pg_temp.open_syncs(current_setting('acc.conn_a2')::uuid) $$,
  $$ values ('paused', 0) $$,
  'pausing stops the connection and cancels its open sync');
select throws_ok($$ select public.request_drive_sync(current_setting('acc.conn_a2')::uuid) $$,
  '22023', 'this drive connection is paused', 'a paused connection does not sync');
select throws_ok($$ select public.set_drive_connection_status(current_setting('acc.conn_a2')::uuid, 'deleted') $$,
  '22023', 'unknown connection status', 'only active and paused can be set');
select public.set_drive_connection_status(current_setting('acc.conn_a2')::uuid, 'active');
select results_eq(
  $$ select (select status::text from public.integration_connections where id = current_setting('acc.conn_a2')::uuid),
            pg_temp.open_syncs(current_setting('acc.conn_a2')::uuid) $$,
  $$ values ('active', 1) $$,
  'resuming queues a sync again');
reset role;

select * from finish();
rollback;
