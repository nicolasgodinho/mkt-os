-- Builder tests for Increment 4 (ExecPlan 0004): decisions the protected TEST_SPEC does not freeze —
-- server-side validation of worker results, participants validation, audit action names, helper
-- privileges and table-level integrity.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e4000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'meetings-admin@builder.test', now(), now());
insert into public.users (id, display_name)
values ('e4000000-0000-4000-8000-000000000001', 'meetings-admin') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e4000000-0000-4000-8000-00000000aaaa', 'Builder Meetings', 'builder-meetings');
insert into public.clients (id, workspace_id, name, slug) values
  ('e4100000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-00000000aaaa', 'Meetings C1', 'meetings-c1');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e4000000-0000-4000-8000-00000000aaaa', 'e4000000-0000-4000-8000-000000000001', 'admin', 'active');

select pg_temp.login_as('e4000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.create_meeting('e4100000-0000-4000-8000-000000000001', 'x', now(),
                    null, '[{"nome": "sem name"}]'::jsonb) $$,
  '22023', null, 'participants must be objects with a name');
select throws_ok($$ select public.create_meeting('e4100000-0000-4000-8000-000000000001', 'x', now(),
                    null, '"Ana"'::jsonb) $$,
  '22023', null, 'participants must be an array');
select set_config('b.m', public.create_meeting('e4100000-0000-4000-8000-000000000001', 'Kickoff',
  now(), null, '[{"name": "Ana"}]'::jsonb, 'clientes/kickoff.m4a')::text, true);
select public.save_meeting_transcript(current_setting('b.m')::uuid, 'Ana: olá.');
select set_config('b.job', public.request_meeting_extraction(current_setting('b.m')::uuid)::text, true);
select set_config('b.tjob', public.request_meeting_transcription(current_setting('b.m')::uuid)::text, true);
reset role;

select 1 from worker.claim_job('b-worker', array['meeting.extract.v1'], 300);
select throws_ok($$ select worker.complete_meeting_extraction(current_setting('b.job')::uuid,
                    'b-worker', 1, '{"proposals": [{"kind": "command", "statement": "x"}]}'::jsonb) $$,
  '22023', null, 'the database rejects proposal kinds outside the contract');
select throws_ok($$ select worker.complete_meeting_extraction(current_setting('b.job')::uuid,
                    'b-worker', 1, '{"proposals": [{"kind": "rule", "statement": "sem tipo"}]}'::jsonb) $$,
  '22023', null, 'the database rejects rules without a rule type');
select is((select status::text from public.jobs where id = current_setting('b.job')::uuid), 'running',
  'a rejected result leaves the job leased (the worker records the failure)');
select throws_ok($$ select worker.complete_meeting_transcription(current_setting('b.job')::uuid,
                    'b-worker', 1, '{"text": "x", "segments": []}'::jsonb) $$,
  '22023', null, 'a completion function refuses jobs of another type');

select 1 from worker.claim_job('b-worker', array['meeting.transcribe.v1'], 300);
select throws_ok($$ select worker.complete_meeting_transcription(current_setting('b.tjob')::uuid,
                    'b-worker', 1, '{"text": "   ", "segments": []}'::jsonb) $$,
  '22023', null, 'a blank transcript is rejected');

select is(worker.complete_meeting_extraction(current_setting('b.job')::uuid, 'b-worker', 1,
  '{"proposals": [{"kind": "rule", "rule_type": "MUST", "subject": " CTA ", "statement": "Use CTA."}]}'::jsonb),
  'completed', 'a valid extraction completes');
select is((select subject from public.meeting_proposals where job_id = current_setting('b.job')::uuid),
  'cta', 'rule subjects are normalized like Client Brain subjects');

-- A failed meeting job is queued again when the same unit of work is requested again.
select worker.fail_job(current_setting('b.tjob')::uuid, 'b-worker', 1,
  '{"code": "recording_not_found"}'::jsonb, false);
select pg_temp.login_as('e4000000-0000-4000-8000-000000000001');
select is(public.request_meeting_transcription(current_setting('b.m')::uuid),
  current_setting('b.tjob')::uuid, 'requesting a failed transcription again reuses the same job');
reset role;
select is((select row(status, attempts, max_attempts > attempts)::text from public.jobs
            where id = current_setting('b.tjob')::uuid),
  '(queued,1,t)', 'the failed job is queued again with its attempt count kept');

select set_eq(
  $$ select action from public.audit_logs where target_id = current_setting('b.m')::uuid $$,
  array['meeting.created', 'meeting.transcript_saved', 'meeting.extraction_requested',
        'meeting.transcription_requested'],
  'audit action names for meetings');

select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'worker' and p.proname in ('lease_for_completion', 'finish_job')
          and (has_function_privilege('jmos_worker', p.oid, 'EXECUTE')
               or has_function_privilege('authenticated', p.oid, 'EXECUTE')))
      or (n.nspname = 'app' and p.proname in ('is_recording_ref', 'require_meeting', 'requeue_if_finished')
          and has_function_privilege('authenticated', p.oid, 'EXECUTE')) $$,
  'meeting helpers are not callable by API roles or the worker');
select throws_ok($$ insert into public.meeting_proposals
                    (meeting_id, client_id, job_id, transcript_revision, kind, statement, rule_type)
                    values (current_setting('b.m')::uuid, 'e4100000-0000-4000-8000-000000000001',
                            current_setting('b.job')::uuid, 1, 'fact', 'x', 'MUST') $$,
  '23514', null, 'only rule proposals carry a rule type (table constraint)');

select * from finish();
rollback;
