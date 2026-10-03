-- Increment 9 / Who may invite and see invitations, tenant isolation, no direct writes
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-9/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

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

-- An Auth identity as Supabase stores it; `p_confirmed` sets email_confirmed_at.
create function pg_temp.make_user(p_id uuid, p_email text, p_confirmed boolean default true)
returns void language plpgsql as $$
begin
  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_email, case when p_confirmed then now() end, now(), now());
  insert into public.users (id, display_name) values (p_id, p_email) on conflict (id) do nothing;
end;
$$;

-- What Supabase Auth sends to the before_user_created hook.
create function pg_temp.signup_event(p_email text) returns jsonb language sql as $$
  select jsonb_build_object('metadata', jsonb_build_object('name', 'before-user-created'),
                            'user', jsonb_build_object('email', p_email, 'aud', 'authenticated'));
$$;

-- ---------------------------------------------------------------------------
-- Fixture (see README): Workspace A {A1, A2}, Workspace B {B1}
-- ---------------------------------------------------------------------------
select pg_temp.make_user(id, email, confirmed) from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'a_admin@acc.test', true),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test', true),
  ('a0000000-0000-4000-8000-000000000009'::uuid, 'a_mgr@acc.test', true),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test', true),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test', true),
  -- People who arrive through invitations.
  ('d0000000-0000-4000-8000-000000000001'::uuid, 'nova@agencia.test', true),
  ('d0000000-0000-4000-8000-000000000002'::uuid, 'aprovador@cliente.test', true),
  ('d0000000-0000-4000-8000-000000000003'::uuid, 'naoconfirmado@agencia.test', false),
  ('d0000000-0000-4000-8000-000000000004'::uuid, 'outra@agencia.test', true)
) as u(id, email, confirmed);

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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000009', 'strategist', '{client.manage}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active');

-- ===========================================================================
-- Who may invite and see invitations (docs/05 §1-§2, docs/11 invariant 1)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select * from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'x@agencia.test', 'creative') $$,
  '42501', 'permission denied', 'inviting internal members needs workspace.manage');
select throws_ok($$ select * from public.invite_client_member('a1000000-0000-4000-8000-0000000000a1', 'x@cliente.test', 'viewer') $$,
  '42501', 'permission denied', 'inviting client members needs client.manage');
select throws_ok($$ select * from public.workspace_members('a0000000-0000-4000-8000-00000000aaaa') $$,
  '42501', 'permission denied', 'listing members needs workspace.manage');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000009');
select set_config('acc.inv_mgr', (select invitation_id::text from public.invite_client_member(
  'a1000000-0000-4000-8000-0000000000a1', 'aprovador@cliente.test', 'approver')), true);
select isnt(current_setting('acc.inv_mgr'), '', 'client.manage is enough to invite client members');
select throws_ok($$ select * from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'x@agencia.test', 'creative') $$,
  '42501', 'permission denied', 'client.manage does not invite internal members');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.inv_a', (select invitation_id::text from public.invite_workspace_member(
  'a0000000-0000-4000-8000-00000000aaaa', 'nova@agencia.test', 'creative')), true);
select set_eq($$ select id from public.invitations $$,
  $$ values (current_setting('acc.inv_a')::uuid), (current_setting('acc.inv_mgr')::uuid) $$,
  'workspace managers see the invitations of their workspace');
select throws_ok($$ select token_hash from public.invitations $$,
  '42501', null, 'nobody reads the token hash through the API');
select throws_ok($$ update public.invitations set status = 'accepted' $$,
  '42501', null, 'invitations cannot be updated directly');
select throws_ok($$ insert into public.invitations (workspace_id, email) values ('a0000000-0000-4000-8000-00000000aaaa', 'z@z.test') $$,
  '42501', null, 'invitations cannot be inserted directly');
reset role;

-- Tenant isolation ----------------------------------------------------------------
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select * from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'x@b.test', 'admin') $$,
  'P0002', 'not found', 'admin B cannot invite into workspace A');
select throws_ok($$ select * from public.invite_client_member('a1000000-0000-4000-8000-0000000000a1', 'x@b.test', 'viewer') $$,
  'P0002', 'not found', 'admin B cannot invite into a workspace A client');
select throws_ok($$ select public.revoke_invitation(current_setting('acc.inv_a')::uuid) $$,
  'P0002', 'not found', 'admin B cannot revoke a workspace A invitation');
select is_empty($$ select 1 from public.invitations $$, 'admin B sees no invitation of workspace A');
select throws_ok($$ select * from public.client_members('a1000000-0000-4000-8000-0000000000a1') $$,
  'P0002', 'not found', 'admin B cannot list workspace A client members');
reset role;

-- Client-side members do not manage access in v0.1 ----------------------------------
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select throws_ok($$ select * from public.invite_client_member('a1000000-0000-4000-8000-0000000000a1', 'x@cliente.test', 'viewer') $$,
  '42501', 'permission denied', 'a client admin cannot invite in v0.1 (client-safe capabilities only)');
select is_empty($$ select 1 from public.invitations $$, 'client members see no invitations');
reset role;

-- Anonymous callers and privileges ----------------------------------------------------
select pg_temp.login_anon();
select throws_ok($$ select 1 from public.invitations $$, '42501', null, 'anon reads nothing');
select throws_ok($$ select * from public.accept_invitation('x') $$, '42501', null,
  'anon cannot accept invitations');
reset role;
select is_empty(
  $$ select 1 where has_table_privilege('authenticated', 'public.invitations', 'INSERT, UPDATE, DELETE, TRUNCATE')
        or has_table_privilege('anon', 'public.invitations', 'SELECT')
        or not (select c.relrowsecurity from pg_class c where c.oid = 'public.invitations'::regclass) $$,
  'invitations have RLS, no API write privileges and no anon access');
select ok(
  not has_function_privilege('authenticated', 'public.hook_before_user_created(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.hook_before_user_created(jsonb)', 'EXECUTE')
  and has_function_privilege('supabase_auth_admin', 'public.hook_before_user_created(jsonb)', 'EXECUTE'),
  'only Supabase Auth runs the signup hook');

select * from finish();
rollback;
