-- Increment 1 acceptance — membership revocation
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-1/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

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
-- Membership revocation: valid access → revoke → same operation denied
-- ===========================================================================
-- Client membership ---------------------------------------------------------
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select set_eq($$ select id from public.clients $$, array['a1000000-0000-4000-8000-0000000000a1']::uuid[],
  'before revocation: approver reads client A1');
select ok('approval.decide' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')),
  'before revocation: approver holds approval.decide');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.revoke_client_member('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002') $$,
  'admin revokes the approver''s client membership');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select is_empty($$ select 1 from public.clients $$,
  'after revocation: the same read returns nothing');
select is(public.client_capabilities('a1000000-0000-4000-8000-0000000000a1'), '{}'::public.capability[],
  'after revocation: no capability remains');
select throws_ok($$ select public.set_client_member('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'client_admin') $$,
  'P0002', 'not found', 'a revoked client member cannot reinstate itself');
reset role;

-- Workspace membership ------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000008');
select set_eq($$ select id from public.clients $$, array['a1000000-0000-4000-8000-0000000000a1', 'a2000000-0000-4000-8000-0000000000a2']::uuid[],
  'before revocation: member with client.view reads workspace clients');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.revoke_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000008') $$,
  'admin revokes the workspace membership');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000008');
select is_empty($$ select 1 from public.clients union all select 1 from public.workspaces $$,
  'after revocation: no client and no workspace is readable');
select is(public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa'), '{}'::public.capability[],
  'after revocation: no workspace capability remains');
reset role;

-- A revoked admin loses privileged operations immediately -----------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000002');
select ok(public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Before Revocation', 'acc-before-rev') is not null,
  'before revocation: second admin creates clients');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.revoke_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000002') $$,
  'admin revokes the second admin');
select isnt_empty(
  $$ select 1 from public.audit_logs
      where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' and actor_id = 'a0000000-0000-4000-8000-000000000001' and target_id = 'a0000000-0000-4000-8000-000000000002' $$,
  'the revocation is audited');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'After Revocation', 'acc-after-rev') $$,
  'P0002', 'not found', 'after revocation: the same privileged operation is denied');
select throws_ok($$ select public.set_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000002', 'admin') $$,
  'P0002', 'not found', 'a revoked admin cannot reinstate itself');
reset role;

select * from finish();
rollback;
