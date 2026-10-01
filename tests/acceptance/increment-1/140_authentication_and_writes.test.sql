-- Increment 1 acceptance — authentication and cross-tenant writes
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-1/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

-- ---------------------------------------------------------------------------
-- Session helpers: impersonate identities the way PostgREST does (claims + role).
-- ---------------------------------------------------------------------------
create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.login_without_subject() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
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

-- ---------------------------------------------------------------------------
-- Fixture (see README): Workspace A {A1, A2}, Workspace B {B1}
-- ---------------------------------------------------------------------------
select pg_temp.make_user(id, email) from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'a_admin@acc.test'),
  ('a0000000-0000-4000-8000-000000000002'::uuid, 'a_admin2@acc.test'),
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a_account@acc.test'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test'),
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a_creative@acc.test'),
  ('a0000000-0000-4000-8000-000000000006'::uuid, 'a_analyst@acc.test'),
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a_contributor@acc.test'),
  ('a0000000-0000-4000-8000-000000000008'::uuid, 'a_contrib_view@acc.test'),
  ('a0000000-0000-4000-8000-000000000009'::uuid, 'a_strat_mgr@acc.test'),
  ('a0000000-0000-4000-8000-00000000000a'::uuid, 'a_invited@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test'),
  ('c1000000-0000-4000-8000-000000000002'::uuid, 'a1_approver@acc.test'),
  ('c1000000-0000-4000-8000-000000000003'::uuid, 'a1_collab@acc.test'),
  ('c1000000-0000-4000-8000-000000000004'::uuid, 'a1_collab_appr@acc.test'),
  ('c1000000-0000-4000-8000-000000000005'::uuid, 'a1_viewer@acc.test'),
  ('c2000000-0000-4000-8000-000000000001'::uuid, 'a2_viewer@acc.test'),
  ('cb000000-0000-4000-8000-000000000001'::uuid, 'b1_approver@acc.test'),
  ('f0000000-0000-4000-8000-000000000001'::uuid, 'outsider@acc.test'),
  ('f0000000-0000-4000-8000-000000000002'::uuid, 'newbie@acc.test')
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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000002', 'admin', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000003', 'account', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000005', 'creative', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000006', 'analyst', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000007', 'contributor', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000008', 'contributor', '{client.view}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000009', 'strategist', '{client.manage}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-00000000000a', 'admin', '{}', 'invited'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'approver', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000003', 'collaborator', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000004', 'collaborator', '{approval.decide}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000005', 'viewer', '{}', 'active'),
  ('a2000000-0000-4000-8000-0000000000a2', 'c2000000-0000-4000-8000-000000000001', 'viewer', '{}', 'active'),
  ('b1000000-0000-4000-8000-0000000000b1', 'cb000000-0000-4000-8000-000000000001', 'approver', '{}', 'active');

-- ===========================================================================
-- Authentication and cross-tenant writes
-- ===========================================================================
-- No authenticated subject -----------------------------------------------------
select pg_temp.login_without_subject();
select is_empty(
  $$ select 1 from public.workspaces union all select 1 from public.clients
     union all select 1 from public.users $$,
  'without an authenticated subject nothing is readable');
select throws_ok($$ select public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Anonymous', 'acc-anon') $$,
  '42501', null, 'without an authenticated subject no write is possible');
select is(public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa'), '{}'::public.capability[],
  'without an authenticated subject no capability is held');
reset role;

select pg_temp.login_anon();
select throws_ok($$ select 1 from public.clients $$, '42501', null, 'anon cannot read clients');
select throws_ok($$ select public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Anonymous', 'acc-anon-2') $$,
  '42501', null, 'anon cannot call the database API');
reset role;
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  'anon can execute no function of the public database API');

-- A subject that belongs to no tenant (forged or stale identity) -----------------
select pg_temp.login_as('0d0d0d0d-0000-4000-8000-00000000dead');
select is_empty($$ select 1 from public.workspaces union all select 1 from public.clients $$,
  'an unknown subject sees nothing');
select throws_ok($$ select public.update_client('a1000000-0000-4000-8000-0000000000a1', 'Forged') $$,
  'P0002', 'not found', 'an unknown subject cannot change a client');
reset role;

-- Direct DML is never a write path, not even for the most privileged member -------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok(
  $$ insert into public.clients (workspace_id, name, slug) values ('a0000000-0000-4000-8000-00000000aaaa', 'Direct', 'acc-direct') $$,
  '42501', null, 'INSERT into clients is denied');
select throws_ok($$ update public.clients set name = 'Direct' where id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  '42501', null, 'UPDATE on clients is denied');
select throws_ok($$ delete from public.clients where id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  '42501', null, 'DELETE on clients is denied');
select throws_ok(
  $$ insert into public.workspace_memberships (workspace_id, user_id, role, status)
     values ('b0000000-0000-4000-8000-00000000bbbb', 'a0000000-0000-4000-8000-000000000001', 'admin', 'active') $$,
  '42501', null, 'INSERT into workspace_memberships is denied');
select throws_ok($$ update public.client_memberships set role = 'client_admin' where client_id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  '42501', null, 'UPDATE on client_memberships is denied');
select throws_ok($$ delete from public.client_memberships where client_id = 'b1000000-0000-4000-8000-0000000000b1' $$,
  '42501', null, 'DELETE on client_memberships is denied');
select throws_ok($$ insert into public.workspaces (name, slug) values ('Direct', 'acc-direct-ws') $$,
  '42501', null, 'INSERT into workspaces is denied');
select throws_ok($$ insert into public.audit_logs (workspace_id, action) values ('a0000000-0000-4000-8000-00000000aaaa', 'forged') $$,
  '42501', null, 'INSERT into audit_logs is denied (append-only through the API)');
select throws_ok($$ delete from public.audit_logs $$,
  '42501', null, 'DELETE on audit_logs is denied');

-- The database API never trusts tenant ids from the payload ------------------------
select throws_ok($$ select public.update_client('b1000000-0000-4000-8000-0000000000b1', 'Hijacked') $$,
  'P0002', 'not found', 'admin A cannot update client B1');
select throws_ok($$ select public.update_client('0d0d0d0d-0000-4000-8000-00000000dead', 'Hijacked') $$,
  'P0002', 'not found', 'a random id yields the identical outcome (no existence leak)');
select throws_ok($$ select public.archive_client('b1000000-0000-4000-8000-0000000000b1') $$,
  'P0002', 'not found', 'admin A cannot archive client B1');
select throws_ok($$ select public.set_client_member('b1000000-0000-4000-8000-0000000000b1', 'a0000000-0000-4000-8000-000000000001', 'client_admin') $$,
  'P0002', 'not found', 'admin A cannot join client B1');
select throws_ok($$ select public.revoke_client_member('b1000000-0000-4000-8000-0000000000b1', 'cb000000-0000-4000-8000-000000000001') $$,
  'P0002', 'not found', 'admin A cannot revoke client B1 members');
select throws_ok($$ select public.set_workspace_member('b0000000-0000-4000-8000-00000000bbbb', 'a0000000-0000-4000-8000-000000000001', 'admin') $$,
  'P0002', 'not found', 'admin A cannot join workspace B');
select throws_ok($$ select public.revoke_workspace_member('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001') $$,
  'P0002', 'not found', 'admin A cannot revoke workspace B members');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.update_client('a2000000-0000-4000-8000-0000000000a2', 'Hijacked') $$,
  'P0002', 'not found', 'a client member cannot reach a sibling client');
reset role;

-- Nothing changed in the other tenant ------------------------------------------
select results_eq(
  $$ select c.name, c.status::text, m.status::text
       from public.clients c
       join public.client_memberships m on m.client_id = c.id
      where c.id = 'b1000000-0000-4000-8000-0000000000b1' $$,
  $$ values ('Secret Client B1', 'active', 'active') $$,
  'client B1 and its membership are untouched');
select is(
  (select count(*)::integer from public.workspace_memberships
    where workspace_id = 'b0000000-0000-4000-8000-00000000bbbb' and status = 'active'),
  1, 'workspace B memberships are untouched');

select * from finish();
rollback;
