-- Increment 3 / Redelivery, fencing after retry, cancel, idempotent requests
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-3/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

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

create function pg_temp.make_user(p_id uuid, p_email text) returns void language plpgsql as $$
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_email, now(), now());
  insert into public.users (id, display_name) values (p_id, p_email) on conflict (id) do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture (see README): Workspace A {A1}, Workspace B {B1}
-- ---------------------------------------------------------------------------
select pg_temp.make_user(id, email) from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'a_admin@acc.test'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test'),
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a_contributor@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test')
) as u(id, email);

insert into public.workspaces (id, name, slug) values
  ('a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Workspace A', 'acc-ws-a'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'Secret Workspace B', 'acc-ws-b');

insert into public.clients (id, workspace_id, name, slug) values
  ('a1000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Client A1', 'acc-client-a1'),
  ('b1000000-0000-4000-8000-0000000000b1', 'b0000000-0000-4000-8000-00000000bbbb', 'Secret Client B1', 'acc-client-b1');

insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status) values
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000007', 'contributor', '{}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active');

-- ===========================================================================
-- A retried job gets a NEW attempt number: stale workers stay fenced out
-- ===========================================================================
select set_config('acc.job', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.redeliver', 1, 'acc-job', '{}'::jsonb, 50, 1))::text, true);
select 1 from worker.claim_job('worker-a', array['acc.redeliver.v1'], 300);
select worker.fail_job(current_setting('acc.job')::uuid, 'worker-a', 1, '{"code": "transient"}'::jsonb, true);

select is((select status::text from public.jobs where id = current_setting('acc.job')::uuid), 'dead_letter',
  'setup: the job exhausted its attempts');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.retry_job(current_setting('acc.job')::uuid);
reset role;

select is((select attempt from worker.claim_job('worker-b', array['acc.redeliver.v1'], 300)), 2,
  'the retried job is leased with an attempt number above every previous one');
select is(worker.complete_job(current_setting('acc.job')::uuid, 'worker-a', 1, '{"from": "worker-a"}'::jsonb), 'lease_lost',
  'a stale worker from the old attempt cannot complete the retried job');
select is(worker.fail_job(current_setting('acc.job')::uuid, 'worker-a', 1, '{"code": "late"}'::jsonb, true), 'lease_lost',
  'a stale worker from the old attempt cannot fail the retried job');
select is(worker.complete_job(current_setting('acc.job')::uuid, 'worker-b', 2, '{"from": "worker-b"}'::jsonb), 'completed',
  'the current attempt completes the job');
select is(worker.complete_job(current_setting('acc.job')::uuid, 'worker-b', 2, '{"from": "again"}'::jsonb), 'duplicate',
  'a duplicate delivery of the completion changes nothing');
select is((select result ->> 'from' from public.jobs where id = current_setting('acc.job')::uuid), 'worker-b',
  'the stored result is the one from the current attempt');

-- ===========================================================================
-- Canceled jobs are never delivered; a retried cancel is delivered once
-- ===========================================================================
select set_config('acc.canceled', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.cancelme', 1, 'acc-canceled', '{}'::jsonb, 50, 3))::text, true);
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.cancel_job(current_setting('acc.canceled')::uuid);
reset role;
select is_empty($$ select 1 from worker.claim_job('worker-a', array['acc.cancelme.v1'], 300) $$,
  'a canceled job is never leased');
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.retry_job(current_setting('acc.canceled')::uuid);
reset role;
select is((select id from worker.claim_job('worker-a', array['acc.cancelme.v1'], 300)), current_setting('acc.canceled')::uuid,
  'after a retry the job is leased again');
select is_empty($$ select 1 from worker.claim_job('worker-b', array['acc.cancelme.v1'], 300) $$,
  'a leased job is never leased twice');

-- ===========================================================================
-- Idempotent requests across completion (docs/11 invariant 6)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.hc', (public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-hc-once'))::text, true);
reset role;
select is((select id from worker.claim_job('worker-a', array['system.healthcheck.v1'], 300)
            where id = current_setting('acc.hc')::uuid), current_setting('acc.hc')::uuid,
  'the worker leases the requested healthcheck');
select is(worker.complete_job(current_setting('acc.hc')::uuid, 'worker-a', 1,
  '{"worker_id": "worker-a", "worker_version": "0.1.0", "checked_at": "2026-10-02T12:00:00+00:00"}'::jsonb),
  'completed', 'the worker completes it');
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select is(public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-hc-once'), current_setting('acc.hc')::uuid,
  'requesting the same unit of work again returns the completed job instead of a new one');
reset role;
select is((select status::text from public.jobs where id = current_setting('acc.hc')::uuid), 'completed',
  'the completed job is not re-run by a repeated request');

-- ===========================================================================
-- Offline worker (docs/03 journey G) and crash recovery
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.offline', (public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'ai.model_check', 'acc-offline'))::text, true);
reset role;
select is((select row(status, lease_owner)::text from public.jobs where id = current_setting('acc.offline')::uuid),
  '(queued,)', 'without a worker, a requested job stays queued and unleased');

select set_config('acc.crash', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.crash', 1, 'acc-crash', '{}'::jsonb, 50, 3))::text, true);
select 1 from worker.claim_job('worker-a', array['acc.crash.v1'], 300);
update public.jobs set lease_until = now() - interval '1 second' where id = current_setting('acc.crash')::uuid;
select is((select attempt from worker.claim_job('worker-b', array['acc.crash.v1'], 300)), 2,
  'an expired lease is recovered and the job is redelivered with a new attempt');
select is(worker.complete_job(current_setting('acc.crash')::uuid, 'worker-a', 1, '{}'::jsonb), 'lease_lost',
  'the crashed worker cannot complete the redelivered job');

select * from finish();
rollback;
