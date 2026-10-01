-- Job visibility and access (docs/05 §1 and §6 visibility boundary, docs/11 invariant 9:
-- clients never see system job details). Jobs are internal and tenant-scoped; the worker API
-- is unreachable from API roles.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create function pg_temp.make_user(p_id uuid, p_email text) returns void language sql as $$
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_email, now(), now());
  insert into public.users (id, display_name) values (p_id, p_email) on conflict (id) do nothing;
$$;

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Fixtures: W1 (client A) and W2 (client C); one client job and one workspace job in W1.
select pg_temp.make_user('a1000000-0000-4000-8000-000000000001', 'w1-admin@test.local');
select pg_temp.make_user('a1000000-0000-4000-8000-000000000003', 'w1-contributor@test.local');
select pg_temp.make_user('a2000000-0000-4000-8000-000000000001', 'w2-admin@test.local');
select pg_temp.make_user('ca000000-0000-4000-8000-000000000001', 'a-approver@test.local');

insert into public.workspaces (id, name, slug) values
  ('f1000000-0000-4000-8000-000000000001', 'Workspace One', 'test-ws-one'),
  ('f2000000-0000-4000-8000-000000000001', 'Workspace Two', 'test-ws-two');
insert into public.clients (id, workspace_id, name, slug) values
  ('c1a00000-0000-4000-8000-00000000000a', 'f1000000-0000-4000-8000-000000000001', 'Client A', 'client-a'),
  ('c2c00000-0000-4000-8000-00000000000c', 'f2000000-0000-4000-8000-000000000001', 'Client C', 'client-c');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('f1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('f1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'contributor', 'active'),
  ('f2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'admin', 'active');
insert into public.client_memberships (client_id, user_id, role, status) values
  ('c1a00000-0000-4000-8000-00000000000a', 'ca000000-0000-4000-8000-000000000001', 'approver', 'active');

insert into public.jobs (id, workspace_id, client_id, type, idempotency_key) values
  ('00b00000-0000-4000-8000-00000000000a', 'f1000000-0000-4000-8000-000000000001',
   'c1a00000-0000-4000-8000-00000000000a', 'test.client_job', 'rls:a'),
  ('00b00000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
   null, 'test.workspace_job', 'rls:w1'),
  ('00b00000-0000-4000-8000-00000000000c', 'f2000000-0000-4000-8000-000000000001',
   'c2c00000-0000-4000-8000-00000000000c', 'test.client_job', 'rls:c');

select worker.heartbeat('rls-worker', 'idle', '0.1.0', array['test.client_job.v1']);

-- Internal admins see their own workspace's jobs only.
select pg_temp.login_as('a1000000-0000-4000-8000-000000000001');
select set_eq(
  $$ select id from public.jobs $$,
  array['00b00000-0000-4000-8000-00000000000a', '00b00000-0000-4000-8000-000000000001']::uuid[],
  'W1 admin sees the client and workspace jobs of W1'
);
select is_empty(
  $$ select 1 from public.jobs where id = '00b00000-0000-4000-8000-00000000000c' $$,
  'W1 admin gets nothing for a guessed job UUID of W2'
);
select isnt_empty(
  $$ select 1 from public.worker_heartbeats where worker_id = 'rls-worker' $$,
  'internal staff can see AI worker health'
);
select throws_ok(
  $$ insert into public.jobs (workspace_id, type, idempotency_key)
     values ('f1000000-0000-4000-8000-000000000001', 'test.injected', 'rls:x') $$,
  '42501', null, 'authenticated cannot insert jobs directly'
);
select throws_ok(
  $$ update public.jobs set status = 'completed' where id = '00b00000-0000-4000-8000-00000000000a' $$,
  '42501', null, 'authenticated cannot change job state directly'
);
select throws_ok(
  $$ select * from worker.claim_job('rogue', array['test.client_job.v1'], 60) $$,
  '42501', null, 'authenticated cannot use the worker API'
);
select throws_ok(
  $$ select app.enqueue_job('f1000000-0000-4000-8000-000000000001', null, 'test.injected', 1, 'rls:y') $$,
  '42501', null, 'authenticated cannot enqueue through the privileged function (Increment 3 adds a checked RPC)'
);
reset role;

select pg_temp.login_as('a2000000-0000-4000-8000-000000000001');
select set_eq(
  $$ select id from public.jobs $$,
  array['00b00000-0000-4000-8000-00000000000c']::uuid[],
  'W2 admin sees only the jobs of W2'
);
reset role;

-- Contributors fail closed until client assignment exists (Increment 1).
select pg_temp.login_as('a1000000-0000-4000-8000-000000000003');
select is_empty($$ select 1 from public.jobs $$, 'contributor sees no jobs');
reset role;

-- Portal boundary: a client member never sees jobs or worker details, even for their own client.
select pg_temp.login_as('ca000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.jobs $$, 'client members never see jobs, even for their own client');
select is_empty($$ select 1 from public.worker_heartbeats $$, 'client members never see AI worker details');
reset role;

set local role anon;
select throws_ok($$ select 1 from public.jobs $$, '42501', null, 'anon cannot read jobs');
reset role;

-- The worker role reaches jobs only through the worker API.
select ok(
  not has_table_privilege('jmos_worker', 'public.jobs', 'SELECT'),
  'jmos_worker cannot read the jobs table directly'
);
select ok(
  has_function_privilege('jmos_worker', 'worker.claim_job(text, text[], integer)', 'EXECUTE'),
  'jmos_worker can lease jobs through the worker API'
);

select * from finish();
rollback;
