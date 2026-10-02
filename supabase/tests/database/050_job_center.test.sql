-- Builder tests for Increment 3 (ExecPlan 0003): decisions the protected TEST_SPEC does not
-- freeze — audit action names, the retry budget cap, the empty summary row, helper privileges.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e3000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'jobs-admin@builder.test', now(), now());
insert into public.users (id, display_name)
values ('e3000000-0000-4000-8000-000000000001', 'jobs-admin') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e3000000-0000-4000-8000-00000000aaaa', 'Builder Jobs', 'builder-jobs');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e3000000-0000-4000-8000-00000000aaaa', 'e3000000-0000-4000-8000-000000000001', 'admin', 'active');

select pg_temp.login_as('e3000000-0000-4000-8000-000000000001');
select is(
  (select row(queued, running, stalled, retry_wait, completed, failed, dead_letter, canceled,
              last_completed_at)::text
     from public.job_center_summary('e3000000-0000-4000-8000-00000000aaaa')),
  '(0,0,0,0,0,0,0,0,)',
  'a workspace without jobs gets one all-zero summary row');
select set_config('b.job', public.request_system_job('e3000000-0000-4000-8000-00000000aaaa',
  'system.healthcheck', 'builder-once')::text, true);
select public.request_system_job('e3000000-0000-4000-8000-00000000aaaa', 'system.healthcheck',
  'builder-once');
select public.cancel_job(current_setting('b.job')::uuid);
select public.retry_job(current_setting('b.job')::uuid);
reset role;

select set_eq(
  $$ select action from public.audit_logs where target_id = current_setting('b.job')::uuid $$,
  array['job.requested', 'job.canceled', 'job.retried'],
  'audit action names for the job center');
select is((select count(*)::integer from public.audit_logs
            where target_id = current_setting('b.job')::uuid and action = 'job.requested'), 1,
  'a repeated request is audited once (only the creation)');
select is((select pipeline_version from public.jobs where id = current_setting('b.job')::uuid),
  'system.healthcheck/1', 'pipeline versions are decided by the server');

-- Retry budget: attempts are capped at 20.
update public.jobs set attempts = 20, max_attempts = 20, status = 'failed', finished_at = now()
 where id = current_setting('b.job')::uuid;
select pg_temp.login_as('e3000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.retry_job(current_setting('b.job')::uuid) $$,
  '22023', null, 'a job that used all 20 attempts cannot be retried');
reset role;
update public.jobs set attempts = 18, max_attempts = 18 where id = current_setting('b.job')::uuid;
select pg_temp.login_as('e3000000-0000-4000-8000-000000000001');
select public.retry_job(current_setting('b.job')::uuid);
reset role;
select is((select max_attempts from public.jobs where id = current_setting('b.job')::uuid), 20,
  'retry grants up to three more attempts within the cap');

select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.proname in ('can_see_job', 'require_manageable_job')
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE')) $$,
  'job center helpers are not callable by API roles');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef
              and p.proname in ('request_system_job', 'cancel_job', 'retry_job', 'job_center_summary')
              and p.proconfig @> array['search_path=""']), 4,
  'job center functions are SECURITY DEFINER with an empty search_path');
select ok(not has_function_privilege('jmos_worker', 'public.retry_job(uuid)', 'EXECUTE'),
  'the worker role cannot use the job center API');
select ok(has_function_privilege('jmos_worker',
  'worker.heartbeat(text, public.worker_status, text, text[], text)', 'EXECUTE'),
  'the worker can still report its active model profile through the heartbeat');

select * from finish();
rollback;
