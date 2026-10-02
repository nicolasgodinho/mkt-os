-- Increment 4 / Proposal review: accept as proposed knowledge, edit, reject
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
-- Setup: an extraction with every kind of proposal
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select public.save_meeting_transcript(current_setting('acc.m_a1')::uuid, 'Transcrição da reunião de kickoff.');
select set_config('acc.job', (public.request_meeting_extraction(current_setting('acc.m_a1')::uuid))::text, true);
reset role;
select 1 from worker.claim_job('acc-worker', array['meeting.extract.v1'], 300);
select worker.complete_meeting_extraction(current_setting('acc.job')::uuid, 'acc-worker', 1,
  '{"proposals": [
     {"kind": "fact", "statement": "Atende três cidades.", "confidence": 0.9, "evidence_quote": "três cidades"},
     {"kind": "decision", "statement": "Priorizar Instagram.", "confidence": 0.8},
     {"kind": "insight", "statement": "Clientes valorizam rapidez.", "confidence": 0.5},
     {"kind": "rule", "rule_type": "MUST", "subject": "reels", "statement": "Talvez testar Reels.", "confidence": 0.3},
     {"kind": "rule", "rule_type": "MUST_NOT", "statement": "Regra sem assunto.", "confidence": 0.7},
     {"kind": "task", "statement": "Enviar briefing.", "confidence": 0.6}
   ]}'::jsonb);
select set_config('acc.p_fact', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid and kind = 'fact'))::text, true);
select set_config('acc.p_decision', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid and kind = 'decision'))::text, true);
select set_config('acc.p_insight', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid and kind = 'insight'))::text, true);
select set_config('acc.p_maybe', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid and subject = 'reels'))::text, true);
select set_config('acc.p_nosubject', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid and kind = 'rule' and subject is null))::text, true);
select set_config('acc.p_task', ((select id from public.meeting_proposals where meeting_id = current_setting('acc.m_a1')::uuid and kind = 'task'))::text, true);

-- ===========================================================================
-- Accepting promotes a proposal into the Client Brain AS PROPOSED knowledge
-- (Increment 2 decision 2; docs/03 journey D; docs/11 invariant 4)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.fact', (public.accept_meeting_proposal(current_setting('acc.p_fact')::uuid))::text, true);
select is(
  (select row(f.status, f.client_id = 'a1000000-0000-4000-8000-0000000000a1', f.source_id = m.transcript_source_id, f.statement)::text
     from public.facts f join public.meetings m on m.id = current_setting('acc.m_a1')::uuid where f.id = current_setting('acc.fact')::uuid),
  '(proposed,t,t,"Atende três cidades.")',
  'an accepted fact enters the Brain as proposed, with the meeting as its source');
select is(
  (select row(status, accepted_item_id = current_setting('acc.fact')::uuid)::text from public.meeting_proposals where id = current_setting('acc.p_fact')::uuid),
  '(accepted,t)', 'the proposal records what it became');
select throws_ok($$ select public.accept_meeting_proposal(current_setting('acc.p_fact')::uuid) $$,
  '22023', null, 'a proposal cannot be accepted twice');

select set_config('acc.decision', (public.accept_meeting_proposal(current_setting('acc.p_decision')::uuid, 'Priorizar Instagram e LinkedIn.'))::text, true);
select is((select statement from public.decisions where id = current_setting('acc.decision')::uuid),
  'Priorizar Instagram e LinkedIn.', 'the reviewer may edit the statement while accepting');
select set_config('acc.insight', (public.accept_meeting_proposal(current_setting('acc.p_insight')::uuid))::text, true);
select is((select status::text from public.insights where id = current_setting('acc.insight')::uuid), 'proposed',
  'an accepted insight is proposed');

select set_config('acc.maybe', (public.accept_meeting_proposal(current_setting('acc.p_maybe')::uuid))::text, true);
select is(
  (select row(type, subject, status)::text from public.rules where id = current_setting('acc.maybe')::uuid),
  '(MUST,reels,proposed)',
  '"maybe test X" accepted as a rule is still only a PROPOSED rule (docs/11 invariant 4)');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where id = current_setting('acc.maybe')::uuid $$,
  'an accepted meeting rule is not effective until someone with rule.activate activates it');
select throws_ok($$ select public.accept_meeting_proposal(current_setting('acc.p_nosubject')::uuid) $$,
  '22023', null, 'a hard rule without subject cannot be accepted as is');
select throws_ok($$ select public.accept_meeting_proposal(current_setting('acc.p_task')::uuid) $$,
  '22023', null, 'tasks cannot be promoted yet (Task arrives with v0.2)');

select lives_ok($$ select public.reject_meeting_proposal(current_setting('acc.p_task')::uuid) $$, 'a proposal can be rejected');
select is((select status::text from public.meeting_proposals where id = current_setting('acc.p_task')::uuid), 'rejected',
  'the rejected proposal is kept with status rejected');
select throws_ok($$ select public.reject_meeting_proposal(current_setting('acc.p_task')::uuid) $$,
  '22023', null, 'a rejected proposal cannot be rejected again');
select throws_ok($$ select public.accept_meeting_proposal(current_setting('acc.p_task')::uuid) $$,
  '22023', null, 'a rejected proposal cannot be accepted');
reset role;

select isnt_empty(
  $$ select 1 from public.audit_logs
      where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' and client_id = 'a1000000-0000-4000-8000-0000000000a1' and actor_id = 'a0000000-0000-4000-8000-000000000004'
        and target_id = current_setting('acc.p_fact')::uuid $$,
  'accepting a proposal is audited');
select isnt_empty(
  $$ select 1 from public.audit_logs where actor_id = 'a0000000-0000-4000-8000-000000000004' and target_id = current_setting('acc.p_task')::uuid $$,
  'rejecting a proposal is audited');

-- Approval is still a separate, capability-checked step ------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact')::uuid) $$,
  '42501', 'permission denied', 'the strategist who accepted cannot approve (knowledge.approve)');
select throws_ok($$ select public.activate_rule(current_setting('acc.maybe')::uuid) $$,
  '42501', 'permission denied', 'the strategist who accepted cannot activate the rule');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact')::uuid) $$,
  'a holder of knowledge.approve approves the accepted fact');
reset role;

-- Who may review ------------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.reject_meeting_proposal(current_setting('acc.p_nosubject')::uuid) $$,
  '42501', 'permission denied', 'reviewing proposals requires knowledge.propose');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.reject_meeting_proposal(current_setting('acc.p_nosubject')::uuid) $$,
  'P0002', 'not found', 'a client approver cannot reach meeting proposals');
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.accept_meeting_proposal(current_setting('acc.p_nosubject')::uuid) $$,
  'P0002', 'not found', 'admin B cannot review proposals of workspace A');
select throws_ok($$ select public.accept_meeting_proposal('0d0d0d0d-0000-4000-8000-00000000dead') $$,
  'P0002', 'not found', 'a nonexistent proposal is not found');
reset role;

select * from finish();
rollback;
