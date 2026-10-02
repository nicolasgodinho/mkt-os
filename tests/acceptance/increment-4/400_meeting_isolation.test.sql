-- Increment 4 / Meeting isolation, internal-only boundary, worker API scope
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-4/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

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
-- Fixture (see README): Workspace A {A1, A2}, Workspace B {B1}
-- ---------------------------------------------------------------------------
select pg_temp.make_user(id, email) from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'a_admin@acc.test'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test'),
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a_creative@acc.test'),
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a_contributor@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test'),
  ('c1000000-0000-4000-8000-000000000002'::uuid, 'a1_approver@acc.test')
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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000005', 'creative', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000007', 'contributor', '{}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'approver', '{}', 'active');

-- Meetings created through the database API; the worker side runs as the privileged owner,
-- exactly like `jmos_worker` calling the `worker.*` API.
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.m_a1', public.create_meeting('a1000000-0000-4000-8000-0000000000a1',
  'Kickoff A1', '2026-10-01 14:00-03', '2026-10-01 15:00-03',
  '[{"name": "Ana (cliente)"}, {"name": "Bruno (agência)"}]'::jsonb, 'clientes/a1/kickoff.m4a')::text, true);
select set_config('acc.m_a2', public.create_meeting('a2000000-0000-4000-8000-0000000000a2',
  'Kickoff A2', '2026-10-01 16:00-03')::text, true);
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_config('acc.m_b1', public.create_meeting('b1000000-0000-4000-8000-0000000000b1',
  'Reunião secreta B1', '2026-10-01 10:00-03')::text, true);
select public.save_meeting_transcript(current_setting('acc.m_b1')::uuid, 'Transcrição secreta de B1.');
reset role;

-- ===========================================================================
-- Setup: a transcript and extracted proposals in A1 (worker path, as the owner)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select public.save_meeting_transcript(current_setting('acc.m_a1')::uuid, 'Ana: o foco é o público família. Talvez testar Reels.');
select set_config('acc.job_a1', (public.request_meeting_extraction(current_setting('acc.m_a1')::uuid))::text, true);
reset role;
select 1 from worker.claim_job('acc-worker', array['meeting.extract.v1'], 300);
select worker.complete_meeting_extraction(current_setting('acc.job_a1')::uuid, 'acc-worker', 1,
  '{"proposals": [{"kind": "fact", "statement": "O foco é o público família.", "confidence": 0.9,
                   "evidence_quote": "o foco é o público família", "time_ref": "00:01"}]}'::jsonb);
select set_config('acc.p_a1', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid))::text, true);

-- ===========================================================================
-- Meetings are internal-only and tenant-isolated (docs/05 §1, docs/11 invariants 1 and 9)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.meetings $$,
  $$ select unnest(array[current_setting('acc.m_a1')::uuid, current_setting('acc.m_a2')::uuid]) $$,
  'admin A sees the meetings of workspace A only');
select is_empty($$ select 1 from public.meetings where id = current_setting('acc.m_b1')::uuid or client_id = 'b1000000-0000-4000-8000-0000000000b1' $$,
  'admin A cannot read a meeting of workspace B, even by id');
select is_empty($$ select 1 from public.meeting_transcripts where meeting_id = current_setting('acc.m_b1')::uuid $$,
  'admin A cannot read the transcript of a meeting of workspace B');
select throws_ok($$ select public.save_meeting_transcript(current_setting('acc.m_b1')::uuid, 'intrusão') $$,
  'P0002', 'not found', 'admin A cannot write the transcript of a meeting of workspace B');
select throws_ok($$ select public.request_meeting_extraction(current_setting('acc.m_b1')::uuid) $$,
  'P0002', 'not found', 'admin A cannot request work on a meeting of workspace B');
select throws_ok($$ select public.create_meeting('b1000000-0000-4000-8000-0000000000b1', 'Intrusão', now()) $$,
  'P0002', 'not found', 'admin A cannot create a meeting for client B1');
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_eq($$ select client_id from public.meetings
     union all select m.client_id from public.meeting_transcripts t join public.meetings m on m.id = t.meeting_id
     union all select client_id from public.meeting_proposals $$, $$ select 'b1000000-0000-4000-8000-0000000000b1'::uuid $$,
  'admin B reads meeting data of client B1 only');
select is_empty($$ select 1 from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid $$,
  'admin B cannot read proposals of workspace A');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select client_id from public.meetings
     union all select m.client_id from public.meeting_transcripts t join public.meetings m on m.id = t.meeting_id
     union all select client_id from public.meeting_proposals $$, 'a client admin reads no meeting, transcript or proposal');
select throws_ok($$ select public.create_meeting('a1000000-0000-4000-8000-0000000000a1', 'Reunião do cliente', now()) $$,
  '42501', 'permission denied', 'a client admin cannot create meetings');
select throws_ok(
  $$ select public.accept_meeting_proposal(current_setting('acc.p_a1')::uuid) $$,
  'P0002', 'not found', 'a client admin cannot reach proposals');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select is_empty($$ select client_id from public.meetings
     union all select m.client_id from public.meeting_transcripts t join public.meetings m on m.id = t.meeting_id
     union all select client_id from public.meeting_proposals $$, 'a client approver reads no meeting data');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select is_empty($$ select client_id from public.meetings
     union all select m.client_id from public.meeting_transcripts t join public.meetings m on m.id = t.meeting_id
     union all select client_id from public.meeting_proposals $$, 'a contributor without grants reads no meeting data (ADR 0002)');
select throws_ok($$ select public.create_meeting('a1000000-0000-4000-8000-0000000000a1', 'Tentativa', now()) $$,
  'P0002', 'not found', 'a contributor without grants cannot reach client A1');
reset role;

select pg_temp.login_anon();
select throws_ok($$ select 1 from public.meetings $$, '42501', null, 'anon cannot read meetings');
select throws_ok($$ select public.create_meeting('a1000000-0000-4000-8000-0000000000a1', 'x', now()) $$,
  '42501', null, 'anon cannot call the meeting API');
reset role;

-- Nobody writes meeting data directly ------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ update public.meetings set title = 'x' where id = current_setting('acc.m_a1')::uuid $$,
  '42501', null, 'meetings are not writable by UPDATE');
select throws_ok($$ update public.meeting_proposals set status = 'accepted' where meeting_id = current_setting('acc.m_a1')::uuid $$,
  '42501', null, 'proposals cannot be accepted by UPDATE');
select throws_ok(
  $$ insert into public.meeting_proposals (meeting_id, client_id, kind, statement)
     values (current_setting('acc.m_a1')::uuid, 'a1000000-0000-4000-8000-0000000000a1', 'rule', 'forjada') $$,
  '42501', null, 'proposals cannot be inserted by API roles');
reset role;
select is_empty(
  $$ select t from unnest(array['meetings', 'meeting_transcripts', 'meeting_proposals']) t
      where has_table_privilege('authenticated', 'public.' || t, 'INSERT, UPDATE, DELETE, TRUNCATE')
         or has_table_privilege('anon', 'public.' || t, 'SELECT')
         or not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) $$,
  'meeting tables have RLS, no API write privileges and no anon access');

-- The worker API never accepts tenant ids and is fenced by the lease --------------
select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      cross join lateral unnest(coalesce(p.proargnames, '{}')) with ordinality a(name, pos)
      where n.nspname = 'worker'
        and coalesce(p.proargmodes[a.pos], 'i') in ('i', 'b', 'v')
        and (a.name ilike '%workspace%' or a.name ilike '%client%' or a.name ilike '%meeting%') $$,
  'no worker function accepts a tenant or meeting id: scope comes from the leased job');
select is_empty($$ select 1 from worker.meeting_for_job(current_setting('acc.job_a1')::uuid, 'acc-worker', 1) $$,
  'a completed job no longer exposes meeting content to the worker');

select * from finish();
rollback;
