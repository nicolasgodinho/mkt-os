-- Increment 1 acceptance — internal-only information and worker boundary
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-1/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

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
-- Internal-only information and the worker boundary (docs/05, docs/11 invariant 9, ADR 0001)
-- ===========================================================================
insert into public.jobs (id, workspace_id, client_id, type, idempotency_key) values
  ('0b000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.client_job', 'acc:a1'),
  ('0b000000-0000-4000-8000-0000000000b1', 'b0000000-0000-4000-8000-00000000bbbb', 'b1000000-0000-4000-8000-0000000000b1', 'acc.client_job', 'acc:b1');
select worker.heartbeat('acc-worker', 'idle', '0.0.0', array['acc.client_job.v1']);

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.set_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'f0000000-0000-4000-8000-000000000002', 'analyst');
reset role;

-- Client roles never receive internal information ---------------------------------
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.jobs $$,
  'client admin never sees system job details, not even for its own client');
select is_empty($$ select 1 from public.worker_heartbeats $$,
  'client admin never sees AI worker details');
select is_empty($$ select 1 from public.audit_logs $$,
  'client admin never sees the internal audit trail');
select is_empty($$ select 1 from public.workspace_memberships $$,
  'client admin never sees internal (workspace) memberships');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select is_empty(
  $$ select 1 from public.jobs union all select 1 from public.worker_heartbeats
     union all select 1 from public.audit_logs $$,
  'viewer never sees job, worker or audit details');
reset role;

-- Internal information never crosses workspaces -----------------------------------
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.jobs $$,
  array['0b000000-0000-4000-8000-0000000000b1']::uuid[],
  'a job of client A1 is invisible to workspace B');
select is_empty($$ select 1 from public.audit_logs where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' $$,
  'the audit trail of workspace A is invisible to workspace B');
reset role;

-- Worker boundary --------------------------------------------------------------
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and has_function_privilege('jmos_worker', p.oid, 'EXECUTE') $$,
  'jmos_worker cannot execute any function of the public database API');
select is_empty(
  $$ select c.relname::text
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r', 'p', 'v', 'm')
        and has_table_privilege('jmos_worker', c.oid, 'SELECT, INSERT, UPDATE, DELETE') $$,
  'jmos_worker has no direct access to any public table (identity, audit, jobs)');
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      cross join lateral unnest(coalesce(p.proargnames, '{}')) with ordinality a(name, pos)
      where n.nspname = 'worker'
        and coalesce(p.proargmodes[a.pos], 'i') in ('i', 'b', 'v')
        and (a.name ilike '%workspace%' or a.name ilike '%client%') $$,
  'no worker function accepts a tenant id: scope comes only from the leased job (ADR 0001)');
select is_empty(
  $$ select 1
       from worker.claim_job('acc-worker', array['acc.client_job.v1'], 60) c
       join public.jobs j on j.id = c.id
      where (c.workspace_id, c.client_id) is distinct from (j.workspace_id, j.client_id) $$,
  'a leased job carries exactly its own tenant scope, never another');

select * from finish();
rollback;
