-- Increment 3 / Job center: visibility, summary, request, cancel, retry
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-3/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(46);

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
-- Setup: jobs in every state, through the queue API (as the privileged owner)
-- ===========================================================================
select set_config('acc.queued_a1', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.cancel', 1, 'acc-queued_a1', '{}'::jsonb, 50, 3))::text, true);
select set_config('acc.queued_ws', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', null, 'acc.workspace', 1, 'acc-queued_ws', '{}'::jsonb, 50, 3))::text, true);
select set_config('acc.waiting', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.waiting', 1, 'acc-waiting', '{}'::jsonb, 50, 3))::text, true);
select 1 from worker.claim_job('acc-worker', array['acc.waiting.v1'], 300);
select worker.fail_job(current_setting('acc.waiting')::uuid, 'acc-worker', 1, '{"code": "transient"}'::jsonb, true);
select set_config('acc.dead', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.dead', 1, 'acc-dead', '{}'::jsonb, 50, 1))::text, true);
select 1 from worker.claim_job('acc-worker', array['acc.dead.v1'], 300);
select worker.fail_job(current_setting('acc.dead')::uuid, 'acc-worker', 1, '{"code": "transient"}'::jsonb, true);
select set_config('acc.failed', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.failed', 1, 'acc-failed', '{}'::jsonb, 50, 3))::text, true);
select 1 from worker.claim_job('acc-worker', array['acc.failed.v1'], 300);
select worker.fail_job(current_setting('acc.failed')::uuid, 'acc-worker', 1, '{"code": "permanent"}'::jsonb, false);
select set_config('acc.done', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.done', 1, 'acc-done', '{}'::jsonb, 50, 3))::text, true);
select 1 from worker.claim_job('acc-worker', array['acc.done.v1'], 300);
select worker.complete_job(current_setting('acc.done')::uuid, 'acc-worker', 1, '{"ok": true}'::jsonb);
select set_config('acc.running', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.running', 1, 'acc-running', '{}'::jsonb, 50, 3))::text, true);
select 1 from worker.claim_job('acc-worker', array['acc.running.v1'], 300);
select set_config('acc.stalled', (app.enqueue_job('a0000000-0000-4000-8000-00000000aaaa', 'a1000000-0000-4000-8000-0000000000a1', 'acc.stalled', 1, 'acc-stalled', '{}'::jsonb, 50, 3))::text, true);
select 1 from worker.claim_job('acc-worker', array['acc.stalled.v1'], 300);
-- The worker died: its lease expired and no claim has recovered it yet.
update public.jobs set lease_until = now() - interval '1 minute' where id = current_setting('acc.stalled')::uuid;
select set_config('acc.secret_b1', (app.enqueue_job('b0000000-0000-4000-8000-00000000bbbb', 'b1000000-0000-4000-8000-0000000000b1', 'acc.secret', 1, 'acc-secret_b1', '{}'::jsonb, 50, 3))::text, true);

-- ===========================================================================
-- Visibility: internal staff of the workspace only (docs/05, docs/11 invariant 9)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.jobs $$,
  $$ select unnest(array[current_setting('acc.queued_a1')::uuid, current_setting('acc.queued_ws')::uuid, current_setting('acc.waiting')::uuid, current_setting('acc.dead')::uuid, current_setting('acc.failed')::uuid,
                         current_setting('acc.done')::uuid, current_setting('acc.running')::uuid, current_setting('acc.stalled')::uuid]) $$,
  'admin A sees every job of workspace A and nothing else');
select is_empty($$ select 1 from public.jobs where id = current_setting('acc.secret_b1')::uuid or workspace_id = 'b0000000-0000-4000-8000-00000000bbbb' $$,
  'admin A cannot see jobs of workspace B, even by id');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select isnt_empty($$ select 1 from public.jobs where id = current_setting('acc.failed')::uuid $$,
  'internal staff with client access see job status and errors');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.jobs $$, 'a client admin never sees jobs');
select is_empty($$ select 1 from public.job_center_summary('a0000000-0000-4000-8000-00000000aaaa') $$,
  'a client admin gets no job center summary');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select is_empty($$ select 1 from public.jobs $$, 'a contributor without grants sees no jobs');
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.jobs $$, $$ select current_setting('acc.secret_b1')::uuid::uuid $$,
  'admin B sees only the jobs of workspace B');
select is_empty($$ select 1 from public.job_center_summary('a0000000-0000-4000-8000-00000000aaaa') $$,
  'admin B gets no summary for workspace A');
reset role;

-- ===========================================================================
-- Job center summary (docs/15 "AI worker health")
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select is(
  (select row(queued, running, stalled, retry_wait, completed, failed, dead_letter, canceled)::text
     from public.job_center_summary('a0000000-0000-4000-8000-00000000aaaa')),
  '(2,2,1,1,1,1,1,0)',
  'counts per status; running includes the stalled job (expired lease, not yet recovered)');
select ok((select last_completed_at is not null from public.job_center_summary('a0000000-0000-4000-8000-00000000aaaa')),
  'the summary reports when a job last completed');
reset role;

-- ===========================================================================
-- Requesting system jobs (workspace.manage)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.requested', (public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-request-1'))::text, true);
select is(
  (select row(status, client_id, created_by, type, schema_version)::text
     from public.jobs where id = current_setting('acc.requested')::uuid),
  row('queued'::public.job_status, null::uuid, 'a0000000-0000-4000-8000-000000000001'::uuid, 'system.healthcheck', 1)::text,
  'an admin requests a workspace-level healthcheck job');
select is(public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-request-1'),
  current_setting('acc.requested')::uuid,
  'requesting again with the same idempotency key returns the same job');
select is((select count(*)::integer from public.jobs where idempotency_key = 'acc-request-1'), 1,
  'a repeated request never creates a second job');
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'ai.model_check', 'acc-request-1') $$,
  '23505', null, 'an idempotency key cannot be reused for a different job');
select set_config('acc.model_check', (public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'ai.model_check', 'acc-request-2'))::text, true);
select is((select model_profile from public.jobs where id = current_setting('acc.model_check')::uuid), 'reasoning',
  'a model check job declares its model profile (docs/08 §4)');
select ok((select pipeline_version is not null from public.jobs where id = current_setting('acc.model_check')::uuid),
  'a requested job records its pipeline version (docs/08 §5)');
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'meeting.extract', 'acc-request-3') $$,
  '22023', null, 'only allow-listed system job types can be requested');
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', '  ') $$,
  '22023', null, 'a blank idempotency key is rejected');
reset role;

select isnt_empty(
  $$ select 1 from public.audit_logs
      where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' and actor_id = 'a0000000-0000-4000-8000-000000000001' and target_id = current_setting('acc.requested')::uuid $$,
  'the job request is audited');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-request-4') $$,
  '42501', 'permission denied', 'requesting system jobs requires workspace.manage');
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-request-5') $$,
  'P0002', 'not found', 'admin B cannot request jobs in workspace A');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-request-6') $$,
  'P0002', 'not found', 'a client admin cannot request jobs');
reset role;
select pg_temp.login_anon();
select throws_ok($$ select public.request_system_job('a0000000-0000-4000-8000-00000000aaaa', 'system.healthcheck', 'acc-request-7') $$,
  '42501', null, 'anon cannot request jobs');
reset role;

-- ===========================================================================
-- Cancel (queued or waiting jobs only)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.cancel_job(current_setting('acc.queued_a1')::uuid) $$,
  '42501', 'permission denied', 'canceling requires workspace.manage');
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.cancel_job(current_setting('acc.queued_a1')::uuid) $$,
  'P0002', 'not found', 'admin B cannot cancel a job of workspace A');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.cancel_job(current_setting('acc.queued_a1')::uuid) $$,
  'P0002', 'not found', 'a client admin cannot cancel jobs');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.cancel_job(current_setting('acc.queued_a1')::uuid) $$, 'an admin cancels a queued job');
select is((select row(status, finished_at is not null)::text from public.jobs where id = current_setting('acc.queued_a1')::uuid),
  '(canceled,t)', 'the canceled job is terminal');
select throws_ok($$ select public.cancel_job(current_setting('acc.queued_a1')::uuid) $$,
  '22023', null, 'a canceled job cannot be canceled again');
select lives_ok($$ select public.cancel_job(current_setting('acc.waiting')::uuid) $$,
  'a job waiting for a retry can be canceled');
select throws_ok($$ select public.cancel_job(current_setting('acc.running')::uuid) $$,
  '22023', null, 'a running job cannot be canceled (the worker holds its lease)');
select throws_ok($$ select public.cancel_job(current_setting('acc.done')::uuid) $$,
  '22023', null, 'a completed job cannot be canceled');
select throws_ok($$ select public.cancel_job('0d0d0d0d-0000-4000-8000-00000000dead') $$,
  'P0002', 'not found', 'a nonexistent job is not found');
reset role;

select isnt_empty(
  $$ select 1 from public.audit_logs where actor_id = 'a0000000-0000-4000-8000-000000000001' and target_id = current_setting('acc.queued_a1')::uuid $$,
  'the cancellation is audited');

-- ===========================================================================
-- Retry (failed, dead-lettered or canceled jobs; attempts are never reset)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.retry_job(current_setting('acc.dead')::uuid) $$,
  '42501', 'permission denied', 'retrying requires workspace.manage');
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.retry_job(current_setting('acc.dead')::uuid) $$,
  'P0002', 'not found', 'admin B cannot retry a job of workspace A');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.retry_job(current_setting('acc.dead')::uuid) $$, 'an admin retries a dead-lettered job');
select is(
  (select row(status, finished_at is null, attempts, max_attempts > attempts)::text
     from public.jobs where id = current_setting('acc.dead')::uuid),
  '(queued,t,1,t)',
  'the retried job is queued again, keeps its attempt count and has a new attempt available');
select lives_ok($$ select public.retry_job(current_setting('acc.failed')::uuid) $$, 'a permanently failed job can be retried');
select lives_ok($$ select public.retry_job(current_setting('acc.queued_a1')::uuid) $$, 'a canceled job can be retried');
select throws_ok($$ select public.retry_job(current_setting('acc.done')::uuid) $$,
  '22023', null, 'a completed job cannot be retried');
select throws_ok($$ select public.retry_job(current_setting('acc.queued_ws')::uuid) $$,
  '22023', null, 'a queued job cannot be retried');
select throws_ok($$ select public.retry_job(current_setting('acc.running')::uuid) $$,
  '22023', null, 'a running job cannot be retried');
reset role;

select isnt_empty(
  $$ select 1 from public.audit_logs where actor_id = 'a0000000-0000-4000-8000-000000000001' and target_id = current_setting('acc.dead')::uuid $$,
  'the retry is audited');

-- ===========================================================================
-- Nobody changes jobs directly
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ update public.jobs set status = 'completed' where id = current_setting('acc.running')::uuid $$,
  '42501', null, 'even an admin cannot change a job by UPDATE');
select throws_ok(
  $$ insert into public.jobs (workspace_id, type, idempotency_key) values ('a0000000-0000-4000-8000-00000000aaaa', 'acc.forged', 'acc-forged') $$,
  '42501', null, 'even an admin cannot insert a job directly');
reset role;

select * from finish();
rollback;
