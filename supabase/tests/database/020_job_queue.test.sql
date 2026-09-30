-- Job queue state machine (docs/04 "AI Job", docs/08 §5, docs/11 invariant 6).
-- At-least-once delivery made safe by idempotent enqueue, fenced leases and idempotent completion.
-- Runs as the migration owner: the worker functions are SECURITY DEFINER, so behavior does not
-- depend on the caller. Caller privileges are covered in 000_platform_guards and 021.
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

-- ---------------------------------------------------------------------------
-- Fixtures and helpers
-- ---------------------------------------------------------------------------
insert into public.workspaces (id, name, slug) values
  ('f1000000-0000-4000-8000-000000000001', 'Workspace One', 'test-ws-one'),
  ('f2000000-0000-4000-8000-000000000001', 'Workspace Two', 'test-ws-two');
insert into public.clients (id, workspace_id, name, slug) values
  ('c1a00000-0000-4000-8000-00000000000a', 'f1000000-0000-4000-8000-000000000001', 'Client A', 'client-a'),
  ('c2c00000-0000-4000-8000-00000000000c', 'f2000000-0000-4000-8000-000000000001', 'Client C', 'client-c');

create temp table t_jobs (name text primary key, id uuid not null);

create function pg_temp.jid(p_name text) returns uuid language sql as $$
  select id from t_jobs where name = p_name
$$;

-- Enqueues a W1/client A job and remembers its id under p_name.
create function pg_temp.enqueue(p_name text, p_type text, p_max_attempts integer default 3,
                                p_priority integer default 50) returns uuid
language plpgsql as $$
declare
  v_id uuid;
begin
  v_id := app.enqueue_job(
    p_workspace_id => 'f1000000-0000-4000-8000-000000000001',
    p_client_id => 'c1a00000-0000-4000-8000-00000000000a',
    p_type => p_type,
    p_schema_version => 1,
    p_idempotency_key => 'test:' || p_name,
    p_input => '{}'::jsonb,
    p_priority => p_priority,
    p_max_attempts => p_max_attempts
  );
  insert into t_jobs (name, id) values (p_name, v_id) on conflict (name) do nothing;
  return v_id;
end;
$$;

-- Leases the next job of one type and returns the attempt number (null when nothing is due).
create function pg_temp.claim(p_worker text, p_type text) returns table (id uuid, attempt integer)
language sql as $$
  select c.id, c.attempt from worker.claim_job(p_worker, array[p_type || '.v1'], 60) c
$$;

create function pg_temp.make_due(p_name text) returns void language sql as $$
  update public.jobs set run_after = now() - interval '1 second' where id = pg_temp.jid(p_name)
$$;

create function pg_temp.expire_lease(p_name text) returns void language sql as $$
  update public.jobs set lease_until = now() - interval '1 second' where id = pg_temp.jid(p_name)
$$;

-- ---------------------------------------------------------------------------
-- Idempotent enqueue
-- ---------------------------------------------------------------------------
select pg_temp.enqueue('j1', 'test.alpha');

select is(
  pg_temp.enqueue('j1', 'test.alpha'), pg_temp.jid('j1'),
  'enqueueing the same idempotency key returns the same job'
);
select is(
  (select count(*)::integer from public.jobs where idempotency_key = 'test:j1'), 1,
  'a duplicate enqueue does not create a second job'
);
select throws_ok(
  $$ select app.enqueue_job('f1000000-0000-4000-8000-000000000001',
                            'c1a00000-0000-4000-8000-00000000000a', 'test.alpha', 1, 'test:j1',
                            '{"different": true}'::jsonb) $$,
  '23505', null, 'reusing an idempotency key for a different payload is rejected'
);
select throws_ok(
  $$ select app.enqueue_job('f1000000-0000-4000-8000-000000000001',
                            'c2c00000-0000-4000-8000-00000000000c', 'test.alpha', 1, 'test:cross') $$,
  '23503', null, 'a job cannot reference a client of another workspace'
);

-- ---------------------------------------------------------------------------
-- Lease, fencing and idempotent completion
-- ---------------------------------------------------------------------------
select is_empty(
  $$ select * from worker.claim_job('worker-a', array['test.nomatch.v1'], 60) $$,
  'a worker only leases job types it declares'
);
select results_eq(
  $$ select * from pg_temp.claim('worker-a', 'test.alpha') $$,
  $$ values (pg_temp.jid('j1'), 1) $$,
  'worker-a leases j1 as attempt 1'
);
select results_eq(
  $$ select status::text, lease_owner, lease_until > now() from public.jobs where id = pg_temp.jid('j1') $$,
  $$ values ('running', 'worker-a', true) $$,
  'a leased job is running with an owner and a future lease'
);
select is_empty(
  $$ select * from pg_temp.claim('worker-b', 'test.alpha') $$,
  'a leased job is not handed to a second worker'
);
select is(
  worker.complete_job(pg_temp.jid('j1'), 'worker-a', 2, '{"ok": true}'),
  'lease_lost', 'completing with the wrong attempt (fencing token) is rejected'
);
select is(
  worker.complete_job(pg_temp.jid('j1'), 'worker-b', 1, '{"ok": true}'),
  'lease_lost', 'completing from a worker that does not hold the lease is rejected'
);
select is(
  worker.complete_job(pg_temp.jid('j1'), 'worker-a', 1, '{"ok": true}'),
  'completed', 'the lease holder completes the job'
);
select results_eq(
  $$ select status::text, result, finished_at is not null, lease_owner is null
       from public.jobs where id = pg_temp.jid('j1') $$,
  $$ values ('completed', '{"ok": true}'::jsonb, true, true) $$,
  'a completed job stores its result, finish time and releases the lease'
);
select is(
  worker.complete_job(pg_temp.jid('j1'), 'worker-a', 1, '{"ok": false}'),
  'duplicate', 'a redelivered completion is a no-op'
);
select is(
  (select result from public.jobs where id = pg_temp.jid('j1')), '{"ok": true}'::jsonb,
  'a duplicate completion does not overwrite the original result'
);
select is(
  worker.fail_job(pg_temp.jid('j1'), 'worker-a', 1, '{"code": "late"}', true),
  'lease_lost', 'a completed job cannot be failed afterwards'
);

-- ---------------------------------------------------------------------------
-- Retryable failures: exponential backoff, then dead letter
-- ---------------------------------------------------------------------------
select pg_temp.enqueue('j2', 'test.beta', 3);

select is((select attempt from pg_temp.claim('worker-a', 'test.beta')), 1, 'j2 attempt 1 leased');
select is(
  worker.fail_job(pg_temp.jid('j2'), 'worker-a', 1, '{"code": "boom", "message": "transient"}', true),
  'retry_scheduled', 'a retryable failure with attempts left schedules a retry'
);
select results_eq(
  $$ select status::text, run_after - now() from public.jobs where id = pg_temp.jid('j2') $$,
  $$ values ('retry_wait', interval '30 seconds') $$,
  'first retry waits 30 seconds'
);
select is_empty(
  $$ select * from pg_temp.claim('worker-a', 'test.beta') $$,
  'a job waiting for retry is not leased before run_after'
);
select pg_temp.make_due('j2');
select is((select attempt from pg_temp.claim('worker-a', 'test.beta')), 2, 'a due retry is leased as attempt 2');
select is(
  worker.fail_job(pg_temp.jid('j2'), 'worker-a', 2, '{"code": "boom"}', true),
  'retry_scheduled', 'second retryable failure schedules another retry'
);
select is(
  (select run_after - now() from public.jobs where id = pg_temp.jid('j2')), interval '60 seconds',
  'backoff doubles on the second retry'
);
select pg_temp.make_due('j2');
select is((select attempt from pg_temp.claim('worker-a', 'test.beta')), 3, 'last attempt leased');
select is(
  worker.fail_job(pg_temp.jid('j2'), 'worker-a', 3, '{"code": "boom"}', true),
  'dead_letter', 'a retryable failure on the last attempt dead-letters the job'
);
select results_eq(
  $$ select status::text, finished_at is not null, last_error ->> 'code'
       from public.jobs where id = pg_temp.jid('j2') $$,
  $$ values ('dead_letter', true, 'boom') $$,
  'a dead-lettered job keeps its last error for manual retry'
);

-- ---------------------------------------------------------------------------
-- Permanent failure
-- ---------------------------------------------------------------------------
select pg_temp.enqueue('j3', 'test.gamma', 3);
select pg_temp.claim('worker-a', 'test.gamma');
select is(
  worker.fail_job(pg_temp.jid('j3'), 'worker-a', 1, '{"code": "invalid_input"}', false),
  'failed', 'a non-retryable failure fails the job immediately'
);
select results_eq(
  $$ select status::text, attempts from public.jobs where id = pg_temp.jid('j3') $$,
  $$ values ('failed', 1) $$,
  'a permanently failed job is not retried'
);

-- ---------------------------------------------------------------------------
-- Crash recovery: expired leases are re-delivered, and the stale worker is fenced out
-- ---------------------------------------------------------------------------
select pg_temp.enqueue('j4', 'test.delta', 3);
select pg_temp.claim('worker-a', 'test.delta');
select pg_temp.expire_lease('j4');
select results_eq(
  $$ select * from pg_temp.claim('worker-b', 'test.delta') $$,
  $$ values (pg_temp.jid('j4'), 2) $$,
  'an expired lease is recovered and re-leased to another worker as the next attempt'
);
select is(
  worker.complete_job(pg_temp.jid('j4'), 'worker-a', 1, '{"from": "stale"}'),
  'lease_lost', 'the stale worker cannot complete after its lease was reclaimed'
);
select is(
  worker.complete_job(pg_temp.jid('j4'), 'worker-b', 2, '{"from": "current"}'),
  'completed', 'the current lease holder completes the recovered job'
);

select pg_temp.enqueue('j5', 'test.epsilon', 1);
select pg_temp.claim('worker-a', 'test.epsilon');
select pg_temp.expire_lease('j5');
select is_empty(
  $$ select * from pg_temp.claim('worker-b', 'test.epsilon') $$,
  'an expired lease on the last attempt is not re-delivered'
);
select results_eq(
  $$ select status::text, last_error ->> 'code' from public.jobs where id = pg_temp.jid('j5') $$,
  $$ values ('dead_letter', 'lease_expired') $$,
  'an expired lease on the last attempt dead-letters the job'
);

-- ---------------------------------------------------------------------------
-- Lease extension, priority, heartbeat
-- ---------------------------------------------------------------------------
select pg_temp.enqueue('j6', 'test.zeta');
select pg_temp.claim('worker-a', 'test.zeta');
select ok(worker.extend_lease(pg_temp.jid('j6'), 'worker-a', 1, 600), 'the lease holder can extend its lease');
select ok(
  not worker.extend_lease(pg_temp.jid('j6'), 'worker-a', 2, 600),
  'a lease cannot be extended with a stale attempt'
);

select pg_temp.enqueue('j7-low', 'test.eta', 3, 10);
select pg_temp.enqueue('j8-high', 'test.eta', 3, 90);
select is(
  (select id from pg_temp.claim('worker-a', 'test.eta')), pg_temp.jid('j8-high'),
  'higher priority jobs are leased first'
);

select worker.heartbeat('worker-a', 'starting', '0.1.0', array['test.alpha.v1']);
select worker.heartbeat('worker-a', 'idle', '0.1.0', array['test.alpha.v1']);
select results_eq(
  $$ select status::text, job_types from public.worker_heartbeats where worker_id = 'worker-a' $$,
  $$ values ('idle', array['test.alpha.v1']) $$,
  'heartbeat upserts the worker liveness row'
);

-- ---------------------------------------------------------------------------
-- Input validation and structural invariants
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select * from worker.claim_job('bad worker id!', array['test.alpha.v1'], 60) $$,
  '22023', null, 'worker ids are validated'
);
select throws_ok(
  $$ insert into public.jobs (workspace_id, type, idempotency_key)
     values ('f1000000-0000-4000-8000-000000000001', 'NotDotted', 'k') $$,
  '23514', null, 'job types must be dotted lowercase names'
);
select throws_ok(
  $$ update public.jobs set status = 'running' where id = pg_temp.jid('j7-low') $$,
  '23514', null, 'a job cannot be running without a lease'
);
select throws_ok(
  $$ select worker.complete_job(pg_temp.jid('j6'), 'worker-a', 1, '[]'::jsonb) $$,
  '22023', null, 'job results must be JSON objects'
);

select * from finish();
rollback;
