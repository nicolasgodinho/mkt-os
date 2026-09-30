-- Increment 1 acceptance — client isolation
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-1/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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
-- Client isolation (docs/05 §1, docs/11 invariants 1 and 9)
-- ===========================================================================
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select set_eq($$ select id from public.clients $$, array['a1000000-0000-4000-8000-0000000000a1']::uuid[],
  'A1 approver sees exactly client A1');
select is_empty($$ select 1 from public.clients where id in ('a2000000-0000-4000-8000-0000000000a2', 'b1000000-0000-4000-8000-0000000000b1') $$,
  'A1 approver gets nothing for sibling client A2 or client B1, even by id');
select set_eq(
  $$ select id from public.clients where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' or workspace_id = 'b0000000-0000-4000-8000-00000000bbbb' $$,
  array['a1000000-0000-4000-8000-0000000000a1']::uuid[],
  'tenant filters chosen by the caller never expand access');
select is(public.client_capabilities('a2000000-0000-4000-8000-0000000000a2'), '{}'::public.capability[],
  'A1 approver holds no capability on A2');
select is(public.client_capabilities('b1000000-0000-4000-8000-0000000000b1'), '{}'::public.capability[],
  'A1 approver holds no capability on B1');
select is_empty($$ select 1 from public.client_memberships where client_id <> 'a1000000-0000-4000-8000-0000000000a1' $$,
  'client members never see memberships of other clients');
select is_empty($$ select 1 from public.workspace_memberships $$,
  'client members never see internal (workspace) memberships');
select is_empty(
  $$ select 1 from public.users where id in ('c2000000-0000-4000-8000-000000000001', 'cb000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001') $$,
  'client members never see profiles of other clients or other workspaces');
reset role;

select pg_temp.login_as('cb000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.clients $$, array['b1000000-0000-4000-8000-0000000000b1']::uuid[],
  'B1 approver sees exactly client B1');
select is_empty($$ select 1 from public.clients where id in ('a1000000-0000-4000-8000-0000000000a1', 'a2000000-0000-4000-8000-0000000000a2') $$,
  'B1 approver gets nothing for client A1 / A2 ids');
reset role;

select pg_temp.login_as('c2000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.clients $$, array['a2000000-0000-4000-8000-0000000000a2']::uuid[],
  'A2 viewer sees exactly client A2');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select is_empty($$ select 1 from public.clients $$,
  'a contributor sees no client unless explicitly granted (docs/01)');
select is(public.client_capabilities('a1000000-0000-4000-8000-0000000000a1'), '{}'::public.capability[],
  'a contributor without an explicit grant holds no capability on A1');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000008');
select set_eq($$ select id from public.clients $$, array['a1000000-0000-4000-8000-0000000000a1', 'a2000000-0000-4000-8000-0000000000a2']::uuid[],
  'an explicitly granted client.view takes effect only inside the granting workspace');
reset role;

select * from finish();
rollback;
