-- Increment 1 acceptance — roles and capabilities
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-1/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

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
-- Roles and capabilities: role defaults + explicit capabilities (docs/01, docs/05 §2)
-- ===========================================================================
-- Client roles --------------------------------------------------------------
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select ok('approval.decide' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')),
  'approver can decide approvals on its client');
select ok(not (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')
               && array['rule.activate', 'strategy.edit', 'knowledge.approve']::public.capability[]),
  'approver never activates rules or edits strategy/knowledge');
select ok(public.client_capabilities('a1000000-0000-4000-8000-0000000000a1') <@ array['client.view', 'approval.decide', 'request.submit']::public.capability[],
  'approver holds only client-safe capabilities (no implicit extras)');
select throws_ok($$ select public.set_client_member('a1000000-0000-4000-8000-0000000000a1', 'f0000000-0000-4000-8000-000000000002', 'viewer') $$,
  '42501', 'permission denied', 'approver cannot manage client memberships');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000003');
select ok('request.submit' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')),
  'collaborator can submit requests');
select ok(not ('approval.decide' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1'))),
  'collaborator cannot approve without a separate grant');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000004');
select ok('approval.decide' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')),
  'a separately granted approval.decide takes effect for a collaborator');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select set_eq($$ select unnest(public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')) $$,
  array['client.view']::public.capability[],
  'viewer is read-only: client.view only');
select throws_ok($$ select public.update_client('a1000000-0000-4000-8000-0000000000a1', 'Renamed by viewer') $$,
  '42501', 'permission denied', 'viewer cannot update its client');
select throws_ok($$ select public.archive_client('a1000000-0000-4000-8000-0000000000a1') $$,
  '42501', 'permission denied', 'viewer cannot archive its client');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select ok('client.view' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')),
  'client admin can view its client');
select ok(public.client_capabilities('a1000000-0000-4000-8000-0000000000a1') <@ array['client.view', 'approval.decide', 'request.submit']::public.capability[],
  'client admin holds only client-safe capabilities');
select throws_ok($$ select public.update_client('a1000000-0000-4000-8000-0000000000a1', 'Renamed by client admin') $$,
  '42501', 'permission denied', 'client admin cannot change internal client records');
select throws_ok($$ select public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Rogue', 'acc-rogue') $$,
  'P0002', 'not found', 'client admin has no access to internal workspace areas');
reset role;

-- Internal roles ------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select is(public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa'), '{}'::public.capability[],
  'contributor has no default capability (task-scoped, docs/01)');
select throws_ok($$ select public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Rogue', 'acc-rogue-c') $$,
  '42501', 'permission denied', 'contributor cannot create clients');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select ok(not (public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa') && array['rule.activate', 'approval.decide', 'publication.schedule', 'publication.publish', 'integration.manage', 'workspace.manage', 'client.manage', 'admin.support']::public.capability[]),
  'account holds no high-risk capability by default (docs/05 §2)');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select ok(not (public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa') && array['rule.activate', 'approval.decide', 'publication.schedule', 'publication.publish', 'integration.manage', 'workspace.manage', 'client.manage', 'admin.support']::public.capability[]),
  'strategist holds no high-risk capability by default (docs/05 §2)');
select throws_ok($$ select public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Rogue', 'acc-rogue-s') $$,
  '42501', 'permission denied', 'strategist without client.manage cannot create clients');
select throws_ok($$ select public.set_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'f0000000-0000-4000-8000-000000000002', 'analyst') $$,
  '42501', 'permission denied', 'strategist without workspace.manage cannot change memberships');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select ok(not (public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa') && array['rule.activate', 'approval.decide', 'publication.schedule', 'publication.publish', 'integration.manage', 'workspace.manage', 'client.manage', 'admin.support']::public.capability[]),
  'creative holds no high-risk capability by default (docs/05 §2)');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000006');
select ok(not (public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa') && array['rule.activate', 'approval.decide', 'publication.schedule', 'publication.publish', 'integration.manage', 'workspace.manage', 'client.manage', 'admin.support']::public.capability[]),
  'analyst holds no high-risk capability by default (docs/05 §2)');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000009');
select ok(public.create_client('a0000000-0000-4000-8000-00000000aaaa', 'Managed Client', 'acc-managed') is not null,
  'an explicitly granted client.manage takes effect');
select throws_ok($$ select public.create_client('b0000000-0000-4000-8000-00000000bbbb', 'Rogue', 'acc-rogue-sm') $$,
  'P0002', 'not found', 'an explicit capability never reaches another workspace');
reset role;

-- Privileged membership management and its audit trail ------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.set_client_member('a1000000-0000-4000-8000-0000000000a1', 'f0000000-0000-4000-8000-000000000002', 'viewer',
                                     array['rule.activate']::public.capability[]) $$,
  '22023', null, 'client memberships cannot hold internal capabilities');
select lives_ok($$ select public.set_client_member('a1000000-0000-4000-8000-0000000000a1', 'f0000000-0000-4000-8000-000000000002', 'viewer') $$,
  'admin (client.manage) can add a client member');
select lives_ok($$ select public.set_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'f0000000-0000-4000-8000-000000000001', 'analyst') $$,
  'admin (workspace.manage) can add a workspace member');
select isnt_empty(
  $$ select 1 from public.audit_logs
      where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' and actor_id = 'a0000000-0000-4000-8000-000000000001' and target_id = 'f0000000-0000-4000-8000-000000000001' $$,
  'membership changes are audited with workspace, actor and target (docs/05 §6)');
reset role;

select pg_temp.login_as('f0000000-0000-4000-8000-000000000002');
select set_eq($$ select id from public.clients $$, array['a1000000-0000-4000-8000-0000000000a1']::uuid[],
  'the newly added client member sees exactly its client');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select is_empty($$ select 1 from public.audit_logs $$,
  'members without audit.view cannot read the audit trail');
reset role;

select * from finish();
rollback;
