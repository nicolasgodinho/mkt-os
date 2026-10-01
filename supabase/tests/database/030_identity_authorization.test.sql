-- Builder tests for Increment 1 (ExecPlan 0001). They cover builder decisions that the protected
-- TEST_SPEC deliberately does not freeze: the exact default capability table (D1), the profile
-- trigger, audit immutability, membership guard rails and input validation.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- D1: default capability table
-- ---------------------------------------------------------------------------
select set_eq($$ select unnest(app.workspace_role_defaults('account')) $$,
  array['client.view', 'knowledge.propose', 'approval.request', 'request.submit',
        'request.triage', 'project.manage']::public.capability[],
  'account defaults');
select set_eq($$ select unnest(app.workspace_role_defaults('strategist')) $$,
  array['client.view', 'strategy.edit', 'knowledge.propose', 'content.create']::public.capability[],
  'strategist defaults');
select set_eq($$ select unnest(app.workspace_role_defaults('creative')) $$,
  array['client.view', 'content.create', 'content.edit', 'content.review_internal']::public.capability[],
  'creative defaults');
select set_eq($$ select unnest(app.workspace_role_defaults('analyst')) $$,
  array['client.view', 'knowledge.propose']::public.capability[],
  'analyst defaults');
select set_eq($$ select unnest(app.client_role_defaults('client_admin')) $$,
  array['client.view', 'approval.decide', 'request.submit']::public.capability[],
  'client_admin defaults');
select set_eq($$ select unnest(app.client_role_defaults('approver')) $$,
  array['client.view', 'approval.decide']::public.capability[],
  'approver defaults');
select set_eq($$ select unnest(app.client_role_defaults('collaborator')) $$,
  array['client.view', 'request.submit']::public.capability[],
  'collaborator defaults');
select is(app.normalize_capabilities(array['client.view', 'client.view', 'audit.view']::public.capability[]),
  array['client.view', 'audit.view']::public.capability[],
  'capabilities are de-duplicated and returned in enum order');

-- ---------------------------------------------------------------------------
-- Profile created from the Auth identity
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values ('d0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'profile@test.local',
        '{"display_name": "  Maria Teste  "}', now(), now());
select results_eq(
  $$ select display_name from public.users where id = 'd0000000-0000-4000-8000-000000000001' $$,
  $$ values ('Maria Teste') $$,
  'a new Auth identity gets an application profile with its trimmed display name');

-- ---------------------------------------------------------------------------
-- Fixture for guard rails
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('d0000000-0000-4000-8000-00000000000a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'solo-admin@test.local', now(), now()),
  ('d0000000-0000-4000-8000-00000000000b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff@test.local', now(), now()),
  ('d0000000-0000-4000-8000-00000000000c', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'client-user@test.local', now(), now());
insert into public.workspaces (id, name, slug) values
  ('d0000000-0000-4000-8000-0000000000f1', 'Guard Workspace', 'guard-ws');
insert into public.clients (id, workspace_id, name, slug) values
  ('d0000000-0000-4000-8000-0000000000c1', 'd0000000-0000-4000-8000-0000000000f1', 'Guard Client', 'guard-client');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('d0000000-0000-4000-8000-0000000000f1', 'd0000000-0000-4000-8000-00000000000a', 'admin', 'active'),
  ('d0000000-0000-4000-8000-0000000000f1', 'd0000000-0000-4000-8000-00000000000b', 'strategist', 'active');
insert into public.client_memberships (client_id, user_id, role, status) values
  ('d0000000-0000-4000-8000-0000000000c1', 'd0000000-0000-4000-8000-00000000000c', 'viewer', 'active');

select pg_temp.login_as('d0000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$ select public.set_workspace_member('d0000000-0000-4000-8000-0000000000f1',
                                        'd0000000-0000-4000-8000-00000000000a', 'analyst') $$,
  '22023', null, 'members cannot change their own membership');
select throws_ok(
  $$ select public.revoke_workspace_member('d0000000-0000-4000-8000-0000000000f1',
                                           'd0000000-0000-4000-8000-00000000000a') $$,
  '22023', null, 'members cannot revoke themselves');
select throws_ok(
  $$ select public.set_workspace_member('d0000000-0000-4000-8000-0000000000f1',
                                        'd0000000-0000-4000-8000-00000000000c', 'analyst') $$,
  '22023', null, 'a client-side member cannot become an internal member of the same workspace');
select throws_ok(
  $$ select public.set_client_member('d0000000-0000-4000-8000-0000000000c1',
                                     'd0000000-0000-4000-8000-00000000000b', 'viewer') $$,
  '22023', null, 'an internal member cannot hold a client membership in the same workspace');
select throws_ok(
  $$ select public.set_workspace_member('d0000000-0000-4000-8000-0000000000f1',
                                        '0d0d0d0d-0000-4000-8000-00000000beef', 'analyst') $$,
  '22023', null, 'memberships require an existing user');
select throws_ok(
  $$ select public.create_client('d0000000-0000-4000-8000-0000000000f1', 'Bad Slug', 'Bad Slug!') $$,
  '22023', null, 'client slugs are validated');
select throws_ok(
  $$ select public.update_client('d0000000-0000-4000-8000-0000000000c1', '   ') $$,
  '22023', null, 'client names are validated');
select lives_ok(
  $$ select public.archive_client('d0000000-0000-4000-8000-0000000000c1') $$,
  'admin archives a client');
select lives_ok(
  $$ select public.archive_client('d0000000-0000-4000-8000-0000000000c1') $$,
  'archiving an archived client is idempotent');
select is(
  (select count(*)::integer from public.audit_logs
    where client_id = 'd0000000-0000-4000-8000-0000000000c1' and action = 'client.archived'),
  1, 'an idempotent archive is audited once');
reset role;

-- The last active admin cannot be removed (the workspace would become unmanageable).
update public.workspace_memberships set role = 'admin'
 where user_id = 'd0000000-0000-4000-8000-00000000000b';
select pg_temp.login_as('d0000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$ select public.revoke_workspace_member('d0000000-0000-4000-8000-0000000000f1',
                                           'd0000000-0000-4000-8000-00000000000a') $$,
  'an admin can revoke another admin while one active admin remains');
reset role;
select is(
  (select count(*)::integer from public.workspace_memberships
    where workspace_id = 'd0000000-0000-4000-8000-0000000000f1' and role = 'admin' and status = 'active'),
  1, 'exactly one active admin remains');

-- ---------------------------------------------------------------------------
-- Audit trail is append-only, even for the table owner
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.audit_logs set action = 'forged.action' $$,
  '42501', null, 'audit entries cannot be updated, even by the owner');
select throws_ok($$ delete from public.audit_logs $$,
  '42501', null, 'audit entries cannot be deleted, even by the owner');

-- ---------------------------------------------------------------------------
-- Privileges of the new functions
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and not has_function_privilege('authenticated', p.oid, 'EXECUTE') $$,
  'every function of the public database API is executable by signed-in users');

select * from finish();
rollback;
