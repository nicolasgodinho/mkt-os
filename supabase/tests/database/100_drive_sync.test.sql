-- Builder tests for Increment 8 (ExecPlan 0008): decisions the protected TEST_SPEC does not freeze —
-- audit action names, function hardening, table constraints, helper privileges.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create function pg_temp.claims(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e8000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'drive-admin@builder.test', now(), now());
insert into public.users (id, display_name) values
  ('e8000000-0000-4000-8000-000000000001', 'drive-admin') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e8000000-0000-4000-8000-00000000aaaa', 'Builder Drive', 'builder-drive');
insert into public.clients (id, workspace_id, name, slug) values
  ('e8100000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-00000000aaaa', 'Drive C1', 'drive-c1');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e8000000-0000-4000-8000-00000000aaaa', 'e8000000-0000-4000-8000-000000000001', 'admin', 'active');

select pg_temp.claims('e8000000-0000-4000-8000-000000000001');
select set_config('b.conn', public.connect_drive_folder('e8100000-0000-4000-8000-000000000001',
  '1BuilderFolderIdxxxxxxxx')::text, true);
select public.set_drive_connection_status(current_setting('b.conn')::uuid, 'paused');
select public.set_drive_connection_status(current_setting('b.conn')::uuid, 'active');
select public.request_drive_sync(current_setting('b.conn')::uuid);

select set_eq(
  $$ select action from public.audit_logs where target_id = current_setting('b.conn')::uuid $$,
  array['drive.connected', 'drive.paused', 'drive.resumed', 'drive.sync_requested'],
  'audit action names for Drive connections');
select is((select scopes from public.integration_connections where id = current_setting('b.conn')::uuid),
  array['https://www.googleapis.com/auth/drive.readonly'], 'connections are read-only by default');
select throws_ok(
  $$ update public.integration_connections set credential_ref = 'ya29.secret-token!' $$,
  '23514', null, 'the table refuses anything that is not a short credential name');
select throws_ok(
  $$ insert into public.file_records (workspace_id, client_id, connection_id, drive_file_id, name,
                                      mime_type, drive_revision)
     values ('e8000000-0000-4000-8000-00000000aaaa', 'e8100000-0000-4000-8000-000000000001',
             current_setting('b.conn')::uuid, '../etc', 'x', 'text/plain', 'r1') $$,
  '23514', null, 'Drive ids keep their format in the table too');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and p.proconfig @> array['search_path=""']
              and p.proname in ('connect_drive_folder', 'set_drive_connection_status',
                                'request_drive_sync', 'request_file_reindex')), 4,
  'Drive functions are SECURITY DEFINER with an empty search_path');
select ok(not has_function_privilege('authenticated',
  'app.queue_drive_sync(public.integration_connections, timestamptz)', 'EXECUTE'),
  'the queueing helper is not callable by API roles');
select is((select count(*)::integer from public.jobs
            where type = 'drive.sync' and status in ('queued', 'retry_wait', 'running')
              and (input ->> 'connection_id')::uuid = current_setting('b.conn')::uuid), 1,
  'pause, resume and a manual request still leave one open sync');

select * from finish();
rollback;
