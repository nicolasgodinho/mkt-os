-- Tenant isolation for the Identity kernel (docs/05 §1, docs/11 "Database/RLS").
-- Proves: internal members see only their workspace's clients; client members see only their
-- own client; guessed UUIDs leak nothing; unauthenticated and incorrect roles cannot write.
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

-- ---------------------------------------------------------------------------
-- Helpers (session-local)
-- ---------------------------------------------------------------------------
create function pg_temp.make_user(p_id uuid, p_email text) returns void language sql as $$
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_email, now(), now());
  insert into public.users (id, display_name) values (p_id, p_email);
$$;

-- Impersonates a signed-in user the way PostgREST does (JWT claims + role). Undo with RESET ROLE.
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

-- ---------------------------------------------------------------------------
-- Fixtures: workspace W1 (clients A, B) and workspace W2 (client C)
-- ---------------------------------------------------------------------------
select pg_temp.make_user('a1000000-0000-4000-8000-000000000001', 'w1-admin@test.local');
select pg_temp.make_user('a1000000-0000-4000-8000-000000000002', 'w1-strategist@test.local');
select pg_temp.make_user('a1000000-0000-4000-8000-000000000003', 'w1-contributor@test.local');
select pg_temp.make_user('a1000000-0000-4000-8000-000000000004', 'w1-revoked@test.local');
select pg_temp.make_user('a2000000-0000-4000-8000-000000000001', 'w2-admin@test.local');
select pg_temp.make_user('ca000000-0000-4000-8000-000000000001', 'a-approver@test.local');
select pg_temp.make_user('ca000000-0000-4000-8000-000000000002', 'a-collaborator@test.local');
select pg_temp.make_user('cb000000-0000-4000-8000-000000000001', 'b-viewer@test.local');
select pg_temp.make_user('0f000000-0000-4000-8000-000000000001', 'outsider@test.local');

insert into public.workspaces (id, name, slug) values
  ('f1000000-0000-4000-8000-000000000001', 'Workspace One', 'test-ws-one'),
  ('f2000000-0000-4000-8000-000000000001', 'Workspace Two', 'test-ws-two');

insert into public.clients (id, workspace_id, name, slug) values
  ('c1a00000-0000-4000-8000-00000000000a', 'f1000000-0000-4000-8000-000000000001', 'Client A', 'client-a'),
  ('c1b00000-0000-4000-8000-00000000000b', 'f1000000-0000-4000-8000-000000000001', 'Client B', 'client-b'),
  ('c2c00000-0000-4000-8000-00000000000c', 'f2000000-0000-4000-8000-000000000001', 'Client C', 'client-c');

insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('f1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('f1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'strategist', 'active'),
  ('f1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'contributor', 'active'),
  ('f1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000004', 'admin', 'revoked'),
  ('f2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'admin', 'active');

insert into public.client_memberships (client_id, user_id, role, status) values
  ('c1a00000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000001', 'approver', 'active'),
  ('c1a00000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000002', 'collaborator', 'active'),
  ('c1b00000-0000-4000-8000-00000000000b', 'cb000000-0000-4000-8000-000000000001', 'viewer', 'active');

-- ---------------------------------------------------------------------------
-- Internal admin of W1
-- ---------------------------------------------------------------------------
select pg_temp.login_as('a1000000-0000-4000-8000-000000000001');

select set_eq(
  $$ select id from public.clients $$,
  array['c1a00000-0000-4000-8000-00000000000a', 'c1b00000-0000-4000-8000-00000000000b']::uuid[],
  'W1 admin sees exactly the clients of W1'
);
select is_empty(
  $$ select 1 from public.clients where id = 'c2c00000-0000-4000-8000-00000000000c' $$,
  'W1 admin gets nothing for a guessed client UUID of W2'
);
select set_eq(
  $$ select id from public.workspaces $$,
  array['f1000000-0000-4000-8000-000000000001']::uuid[],
  'W1 admin sees only workspace W1'
);
select set_eq(
  $$ select user_id from public.workspace_memberships $$,
  array['a1000000-0000-4000-8000-000000000001']::uuid[],
  'members see only their own workspace membership rows'
);
select set_eq(
  $$ select id from public.users $$,
  array['a1000000-0000-4000-8000-000000000001']::uuid[],
  'users see only their own profile'
);

-- Privileged writes are denied to every API role (performed by services in Increment 1).
select throws_ok(
  $$ insert into public.clients (workspace_id, name, slug)
     values ('f1000000-0000-4000-8000-000000000001', 'Rogue', 'rogue') $$,
  '42501', null, 'authenticated cannot create clients directly'
);
select throws_ok(
  $$ update public.clients set name = 'Renamed' where id = 'c1a00000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'authenticated cannot update clients directly'
);
select throws_ok(
  $$ delete from public.workspaces where id = 'f1000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'authenticated cannot delete workspaces'
);
select throws_ok(
  $$ insert into public.workspace_memberships (workspace_id, user_id, role, status)
     values ('f2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001',
             'admin', 'active') $$,
  '42501', null, 'a member cannot grant themselves access to another workspace'
);
reset role;

-- ---------------------------------------------------------------------------
-- Internal strategist of W1 (non-admin internal role)
-- ---------------------------------------------------------------------------
select pg_temp.login_as('a1000000-0000-4000-8000-000000000002');
select set_eq(
  $$ select id from public.clients $$,
  array['c1a00000-0000-4000-8000-00000000000a', 'c1b00000-0000-4000-8000-00000000000b']::uuid[],
  'W1 strategist sees the clients of W1'
);
reset role;

-- ---------------------------------------------------------------------------
-- Internal admin of W2
-- ---------------------------------------------------------------------------
select pg_temp.login_as('a2000000-0000-4000-8000-000000000001');
select set_eq(
  $$ select id from public.clients $$,
  array['c2c00000-0000-4000-8000-00000000000c']::uuid[],
  'W2 admin sees only the client of W2'
);
select is_empty(
  $$ select 1 from public.clients
      where id in ('c1a00000-0000-4000-8000-00000000000a', 'c1b00000-0000-4000-8000-00000000000b')
     union all
     select 1 from public.workspaces where id = 'f1000000-0000-4000-8000-000000000001' $$,
  'W2 admin gets nothing for guessed W1 client and workspace UUIDs'
);
reset role;

-- ---------------------------------------------------------------------------
-- Client approver of A
-- ---------------------------------------------------------------------------
select pg_temp.login_as('ca000000-0000-4000-8000-000000000001');
select set_eq(
  $$ select id from public.clients $$,
  array['c1a00000-0000-4000-8000-00000000000a']::uuid[],
  'client A approver sees only client A'
);
select is_empty(
  $$ select 1 from public.clients where id = 'c1b00000-0000-4000-8000-00000000000b' $$,
  'client A approver gets nothing for a guessed sibling client UUID (same workspace)'
);
select is_empty(
  $$ select 1 from public.workspaces $$,
  'client members cannot see workspace rows'
);
select set_eq(
  $$ select user_id from public.client_memberships $$,
  array['ca000000-0000-4000-8000-000000000001']::uuid[],
  'client members see only their own client membership, not other members'
);
select throws_ok(
  $$ insert into public.client_memberships (client_id, user_id, role, status)
     values ('c1b00000-0000-4000-8000-00000000000b', 'ca000000-0000-4000-8000-000000000001',
             'client_admin', 'active') $$,
  '42501', null, 'a client member cannot grant themselves access to another client'
);
select throws_ok(
  $$ update public.client_memberships set role = 'client_admin'
      where user_id = 'ca000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'a client member cannot escalate their own role'
);
reset role;

-- ---------------------------------------------------------------------------
-- Client viewer of B
-- ---------------------------------------------------------------------------
select pg_temp.login_as('cb000000-0000-4000-8000-000000000001');
select set_eq(
  $$ select id from public.clients $$,
  array['c1b00000-0000-4000-8000-00000000000b']::uuid[],
  'client B viewer sees only client B'
);
reset role;

-- ---------------------------------------------------------------------------
-- Contributor (fail-closed until explicit assignment exists in Increment 1)
-- ---------------------------------------------------------------------------
select pg_temp.login_as('a1000000-0000-4000-8000-000000000003');
select is_empty($$ select 1 from public.clients $$, 'contributor sees no clients without assignment');
select set_eq(
  $$ select id from public.workspaces $$,
  array['f1000000-0000-4000-8000-000000000001']::uuid[],
  'contributor still sees the workspace they belong to'
);
reset role;

-- ---------------------------------------------------------------------------
-- Revoked membership, outsider, missing identity, anon
-- ---------------------------------------------------------------------------
select pg_temp.login_as('a1000000-0000-4000-8000-000000000004');
select is_empty(
  $$ select 1 from public.clients union all select 1 from public.workspaces $$,
  'a revoked member sees no clients or workspaces'
);
reset role;

select pg_temp.login_as('0f000000-0000-4000-8000-000000000001');
select is_empty(
  $$ select 1 from public.clients
     union all select 1 from public.workspaces
     union all select 1 from public.workspace_memberships
     union all select 1 from public.client_memberships $$,
  'a signed-in user without memberships sees no tenant data'
);
reset role;

select set_config('request.jwt.claims', '', true);
set local role authenticated;
select is_empty(
  $$ select 1 from public.clients union all select 1 from public.users $$,
  'authenticated role without a subject claim sees nothing'
);
reset role;

select pg_temp.login_anon();
select throws_ok($$ select 1 from public.clients $$, '42501', null, 'anon cannot read clients');
select throws_ok($$ select 1 from public.users $$, '42501', null, 'anon cannot read user profiles');
select throws_ok(
  $$ select 1 from public.workspace_memberships $$, '42501', null, 'anon cannot read memberships'
);
reset role;

select * from finish();
rollback;
