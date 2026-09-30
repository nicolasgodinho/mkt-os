-- Explicit audit of the AI Worker boundary (docs/05 §1 "service/worker paths use narrowly-scoped
-- server credentials", docs/08 §5 job contract). Complements the generic guards in 000.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

-- ---------------------------------------------------------------------------
-- Privileges: PUBLIC, schemas, role membership
-- ---------------------------------------------------------------------------
-- A function whose ACL is NULL implicitly grants EXECUTE to PUBLIC (acldefault), so both the
-- explicit and the implicit case are checked.
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where n.nspname in ('app', 'worker')
        and a.grantee = 0
        and a.privilege_type = 'EXECUTE' $$,
  'no private function (app, worker) is executable by PUBLIC'
);
select is_empty(
  $$ select n.nspname::text
       from pg_namespace n
      cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
      where n.nspname in ('app', 'worker')
        and a.grantee = 0 $$,
  'PUBLIC has no privileges on the private schemas'
);
select is_empty(
  $$ select n.nspname || '.' || p.proname
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where p.prosecdef
        and n.nspname in ('public', 'app', 'worker')
        and not ('search_path=""' = any (coalesce(p.proconfig, '{}'))) $$,
  'every SECURITY DEFINER function pins an EMPTY search_path (no schema can be hijacked)'
);
select set_eq(
  $$ select p.proname::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'worker' and p.prosecdef $$,
  array['claim_job', 'complete_job', 'extend_lease', 'fail_job', 'heartbeat'],
  'only the worker API functions run with elevated (definer) rights'
);
select ok(
  not has_schema_privilege('jmos_worker', 'public', 'CREATE')
  and not has_schema_privilege('jmos_worker', 'worker', 'CREATE'),
  'jmos_worker cannot create objects'
);
select ok(
  not pg_has_role('jmos_worker', 'postgres', 'MEMBER')
  and not pg_has_role('jmos_worker', 'service_role', 'MEMBER')
  and not pg_has_role('jmos_worker', 'authenticated', 'MEMBER')
  and not pg_has_role('jmos_worker', 'anon', 'MEMBER'),
  'jmos_worker cannot assume any other role'
);

-- ---------------------------------------------------------------------------
-- Input validation on every entry point
-- ---------------------------------------------------------------------------
insert into public.workspaces (id, name, slug)
values ('f1000000-0000-4000-8000-000000000001', 'Workspace One', 'test-ws-one');

create temp table t_job as
select app.enqueue_job('f1000000-0000-4000-8000-000000000001', null, 'test.boundary', 1,
                       'boundary:1') as id;

select throws_ok(
  $$ select * from worker.claim_job('w', '{}'::text[], 60) $$,
  '22023', null, 'claim requires at least one declared job type'
);
select throws_ok(
  $$ select * from worker.claim_job('w', array['test.boundary.v1'], 5) $$,
  '22023', null, 'claim rejects out-of-range lease lengths'
);
select throws_ok(
  $$ select worker.extend_lease((select id from t_job), 'w', 1, 99999) $$,
  '22023', null, 'extend_lease rejects out-of-range lease lengths'
);
select throws_ok(
  $$ select worker.heartbeat('bad id!', 'idle', '0.1.0', array[]::text[]) $$,
  '22023', null, 'heartbeat validates the worker id'
);
select throws_ok(
  $$ select worker.complete_job('00000000-0000-4000-8000-00000000dead', 'w', 1, '{}') $$,
  'P0002', null, 'completing an unknown job is an error, not a silent no-op'
);

select is(
  (select attempt from worker.claim_job('w', array['test.boundary.v1'], 60)), 1,
  'boundary job leased'
);
select throws_ok(
  $$ select worker.fail_job((select id from t_job), 'w', 1, '{"message": "no code"}', true) $$,
  '22023', null, 'failures must carry an error code'
);
select throws_ok(
  $$ select worker.fail_job((select id from t_job), 'w', 1, '{"code": "x"}', null) $$,
  '22023', null, 'failures must state whether they are retryable'
);
select throws_ok(
  $$ select worker.complete_job((select id from t_job), 'w', 1,
                                jsonb_build_object('blob', repeat('x', 300000))) $$,
  '23514', null, 'oversized results are rejected by the database'
);

-- ---------------------------------------------------------------------------
-- Duplicate work never runs twice
-- ---------------------------------------------------------------------------
select is(
  worker.complete_job((select id from t_job), 'w', 1, '{"ok": true}'), 'completed',
  'boundary job completed'
);
select is(
  app.enqueue_job('f1000000-0000-4000-8000-000000000001', null, 'test.boundary', 1, 'boundary:1'),
  (select id from t_job),
  're-enqueueing completed work returns the existing job'
);
select is_empty(
  $$ select * from worker.claim_job('w2', array['test.boundary.v1'], 60) $$,
  'completed work is not delivered again after a duplicate enqueue'
);
select ok(
  not worker.extend_lease((select id from t_job), 'w', 1, 60),
  'a finished job has no lease to extend'
);

select * from finish();
rollback;
