-- Increment 2 / Knowledge: sources, proposed-first facts/decisions/insights, trust
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-2/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(38);

-- ---------------------------------------------------------------------------
-- Session helpers: impersonate identities the way PostgREST does (claims + role).
-- Ids created during the test are kept in transaction-local settings (acc.*).
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
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a_account@acc.test'),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test'),
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a_creative@acc.test'),
  ('a0000000-0000-4000-8000-000000000006'::uuid, 'a_analyst@acc.test'),
  ('a0000000-0000-4000-8000-000000000007'::uuid, 'a_contributor@acc.test'),
  ('a0000000-0000-4000-8000-000000000008'::uuid, 'a_contrib_view@acc.test'),
  ('a0000000-0000-4000-8000-00000000000a'::uuid, 'a_invited@acc.test'),
  ('a0000000-0000-4000-8000-00000000000b'::uuid, 'a_curator@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test'),
  ('c1000000-0000-4000-8000-000000000002'::uuid, 'a1_approver@acc.test'),
  ('c1000000-0000-4000-8000-000000000004'::uuid, 'a1_collab_appr@acc.test'),
  ('c1000000-0000-4000-8000-000000000005'::uuid, 'a1_viewer@acc.test'),
  ('cb000000-0000-4000-8000-000000000001'::uuid, 'b1_approver@acc.test'),
  ('f0000000-0000-4000-8000-000000000001'::uuid, 'outsider@acc.test')
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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000003', 'account', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000005', 'creative', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000006', 'analyst', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000007', 'contributor', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000008', 'contributor', '{client.view}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-00000000000a', 'admin', '{}', 'invited'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-00000000000b', 'strategist', '{knowledge.approve}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'approver', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000004', 'collaborator', '{approval.decide}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000005', 'viewer', '{}', 'active'),
  ('b1000000-0000-4000-8000-0000000000b1', 'cb000000-0000-4000-8000-000000000001', 'approver', '{}', 'active');

-- Sources, created through the database API (never by direct insert).
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.src_a1', public.create_source('a1000000-0000-4000-8000-0000000000a1',
  'meeting', 'Kickoff com o cliente', 'FIRST_PARTY')::text, true);
select set_config('acc.src_a1_untrusted', public.create_source('a1000000-0000-4000-8000-0000000000a1',
  'website', 'Post de terceiros', 'UNTRUSTED_EXTERNAL', 'https://example.test/post')::text, true);
select set_config('acc.src_a2', public.create_source('a2000000-0000-4000-8000-0000000000a2',
  'document', 'Briefing A2', 'APPROVED_CLIENT')::text, true);
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_config('acc.src_b1', public.create_source('b1000000-0000-4000-8000-0000000000b1',
  'document', 'Briefing secreto B1', 'APPROVED_CLIENT')::text, true);
reset role;

-- ===========================================================================
-- Proposed-first knowledge (decision 2, docs/00 "no silent learning")
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000006');
select set_config('acc.fact', (public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Atende em três cidades'))::text, true);
select is((select status::text from public.facts where id = current_setting('acc.fact')::uuid), 'proposed',
  'an analyst (knowledge.propose) proposes a fact, which starts as proposed');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact')::uuid) $$,
  '42501', 'permission denied', 'proposing does not include approving (knowledge.approve)');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', null, 'Sem fonte') $$,
  '22023', null, 'knowledge requires a source (provenance)');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, '  ') $$,
  '22023', null, 'a blank statement is rejected');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Janela invertida', '2027-01-01', '2026-01-01') $$,
  '22023', null, 'a fact cannot stop being valid before it starts');
select throws_ok($$ select public.create_source('a1000000-0000-4000-8000-0000000000a1', 'document', 'Fonte do sistema', 'SYSTEM') $$,
  '22023', null, 'SYSTEM trust cannot be claimed through the API');
select ok(public.create_source('a1000000-0000-4000-8000-0000000000a1', 'review', 'Avaliação pública', 'UNTRUSTED_EXTERNAL') is not null,
  'untrusted sources can be registered as evidence');
select set_config('acc.fact_u', (public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1_untrusted')::uuid, 'Concorrente diz que somos caros'))::text, true);
select set_config('acc.dec_u', (public.propose_decision('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1_untrusted')::uuid, 'Baixar preços', 'Post de terceiro'))::text, true);
select set_config('acc.ins_u', (public.propose_insight('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1_untrusted')::uuid, 'Percepção de preço alto', 0.4))::text, true);
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.fact_admin', (public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Fundada em 1998'))::text, true);
select is((select status::text from public.facts where id = current_setting('acc.fact_admin')::uuid), 'proposed',
  'even an admin''s fact enters as proposed');
select set_config('acc.dec', (public.propose_decision('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Foco em B2B', 'Ticket maior', '2026-09-01'))::text, true);
select is((select status::text from public.decisions where id = current_setting('acc.dec')::uuid), 'proposed',
  'even an admin''s decision enters as proposed');
select set_config('acc.ins', (public.propose_insight('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Prova social converte', 0.7))::text, true);
select is((select status::text from public.insights where id = current_setting('acc.ins')::uuid), 'proposed',
  'even an admin''s insight enters as proposed');
select set_config('acc.rule', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'cta', 'Todo post tem CTA'))::text, true);
select is((select status::text from public.rules where id = current_setting('acc.rule')::uuid), 'proposed',
  'even an admin''s rule enters as proposed');
reset role;

-- Approval and rejection (knowledge.approve) ---------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-00000000000b');
select lives_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact')::uuid) $$,
  'a holder of knowledge.approve approves a proposed fact');
select is((select status::text from public.facts where id = current_setting('acc.fact')::uuid), 'active',
  'the approved fact is active');
select is((select approved_by from public.facts where id = current_setting('acc.fact')::uuid), 'a0000000-0000-4000-8000-00000000000b'::uuid,
  'the approver is recorded on the fact');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact')::uuid) $$,
  '22023', null, 'an active fact cannot be approved again');
select lives_ok($$ select public.reject_knowledge('decision', current_setting('acc.dec')::uuid) $$,
  'a proposed decision can be rejected');
select is((select status::text from public.decisions where id = current_setting('acc.dec')::uuid), 'rejected',
  'the rejected decision is kept with status rejected');
select throws_ok($$ select public.approve_knowledge('decision', current_setting('acc.dec')::uuid) $$,
  '22023', null, 'a rejected decision cannot be approved');
select lives_ok($$ select public.approve_knowledge('insight', current_setting('acc.ins')::uuid) $$,
  'a proposed insight can be approved');
select is((select status::text from public.insights where id = current_setting('acc.ins')::uuid), 'active',
  'the approved insight is active');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.ins')::uuid) $$,
  'P0002', 'not found', 'an id of another kind is not found');
select throws_ok($$ select public.approve_knowledge('fact', '0d0d0d0d-0000-4000-8000-00000000dead') $$,
  'P0002', 'not found', 'a nonexistent fact is not found');
select throws_ok($$ select public.activate_rule(current_setting('acc.rule')::uuid) $$,
  '42501', 'permission denied', 'knowledge.approve does not include rule.activate');

-- Untrusted sources are not truth (decision 4, docs/02 §5) -----------------------
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact_u')::uuid) $$,
  '22023', null, 'a fact from an UNTRUSTED_EXTERNAL source cannot be approved');
select is((select status::text from public.facts where id = current_setting('acc.fact_u')::uuid), 'proposed',
  'the untrusted fact stays proposed');
select lives_ok($$ select public.approve_knowledge('insight', current_setting('acc.ins_u')::uuid) $$,
  'an insight (interpretation) from an untrusted source can be approved');
select lives_ok($$ select public.reject_knowledge('fact', current_setting('acc.fact_u')::uuid) $$,
  'an untrusted fact can be rejected');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.approve_knowledge('decision', current_setting('acc.dec_u')::uuid) $$,
  '22023', null, 'not even an admin approves a decision from an untrusted source');
reset role;

-- Audit (docs/05 §6) ----------------------------------------------------------
select isnt_empty(
  $$ select 1 from public.audit_logs
      where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' and client_id = 'a1000000-0000-4000-8000-0000000000a1'
        and actor_id = 'a0000000-0000-4000-8000-00000000000b' and target_id = current_setting('acc.fact')::uuid $$,
  'the approval is audited with workspace, client, actor and target');
select isnt_empty(
  $$ select 1 from public.audit_logs where actor_id = 'a0000000-0000-4000-8000-00000000000b' and target_id = current_setting('acc.dec')::uuid $$,
  'the rejection is audited');

-- Who cannot propose or approve -----------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.propose_insight('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Ideia', 0.5) $$,
  '42501', 'permission denied', 'a creative (no knowledge.propose) cannot propose');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact_admin')::uuid) $$,
  '42501', 'permission denied', 'a strategist cannot approve knowledge');
select throws_ok($$ select public.reject_knowledge('fact', current_setting('acc.fact_admin')::uuid) $$,
  '42501', 'permission denied', 'a strategist cannot reject knowledge');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select ok(public.propose_decision('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Calendário quinzenal') is not null,
  'an account manager (knowledge.propose) proposes a decision');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact_admin')::uuid) $$,
  'P0002', 'not found', 'a client approver cannot approve internal knowledge');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Sugestão') $$,
  '42501', 'permission denied', 'a client approver cannot propose knowledge');
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.reject_knowledge('fact', current_setting('acc.fact_admin')::uuid) $$,
  'P0002', 'not found', 'admin B cannot reject knowledge of client A1');
reset role;

select is((select status::text from public.facts where id = current_setting('acc.fact_admin')::uuid), 'proposed',
  'denied attempts left the admin''s fact proposed');

select * from finish();
rollback;
