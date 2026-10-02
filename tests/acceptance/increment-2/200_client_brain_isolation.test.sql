-- Increment 2 / Client Brain isolation, internal-only boundary, direct-write denial
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-2/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(50);

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
-- Setup through the API: Client Brain content in A1, A2 and B1
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.brand_a1', (public.save_brand_profile('a1000000-0000-4000-8000-0000000000a1', 'Clínica odontológica', 'Acolhedora',
  'Próxima e técnica', array['https://example.test/moodboard']))::text, true);
select set_config('acc.aud_a1', (public.save_audience('a1000000-0000-4000-8000-0000000000a1', null, 'Famílias', 'Pais com filhos pequenos'))::text, true);
select set_config('acc.offer_a1', (public.save_offer('a1000000-0000-4000-8000-0000000000a1', null, 'Check-up', 'Avaliação completa', null, null))::text, true);
select set_config('acc.region_a1', (public.save_region('a1000000-0000-4000-8000-0000000000a1', null, 'Zona Sul', 'Bairros da zona sul'))::text, true);
select set_config('acc.fact_a1', (public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Atende aos sábados'))::text, true);
select public.approve_knowledge('fact', current_setting('acc.fact_a1')::uuid);
select set_config('acc.fact_a1p', (public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Abre filial em 2027'))::text, true);
select set_config('acc.dec_a1', (public.propose_decision('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Foco em implantes', 'Margem maior'))::text, true);
select set_config('acc.ins_a1', (public.propose_insight('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Vídeos curtos convertem mais', 0.6))::text, true);
select set_config('acc.rule_a1', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'cta', 'Todo post tem CTA'))::text, true);
select public.activate_rule(current_setting('acc.rule_a1')::uuid);
select set_config('acc.rule_a1p', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'preco', 'Nunca citar preço'))::text, true);
select set_config('acc.fact_a2', (public.propose_fact('a2000000-0000-4000-8000-0000000000a2', current_setting('acc.src_a2')::uuid, 'Fato do cliente A2'))::text, true);
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_config('acc.aud_b1', (public.save_audience('b1000000-0000-4000-8000-0000000000b1', null, 'Público secreto', 'Somente B'))::text, true);
select set_config('acc.fact_b1p', (public.propose_fact('b1000000-0000-4000-8000-0000000000b1', current_setting('acc.src_b1')::uuid, 'Fato secreto de B1'))::text, true);
select set_config('acc.rule_b1', (public.propose_rule('b1000000-0000-4000-8000-0000000000b1', current_setting('acc.src_b1')::uuid, 'MUST', 'segredo', 'Regra secreta de B1'))::text, true);
select public.activate_rule(current_setting('acc.rule_b1')::uuid);
select set_config('acc.rule_b1p', (public.propose_rule('b1000000-0000-4000-8000-0000000000b1', current_setting('acc.src_b1')::uuid, 'AVOID', null, 'Proposta secreta de B1'))::text, true);
reset role;

-- ===========================================================================
-- Workspace isolation (docs/05 §1, docs/11 invariant 1)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_eq($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, $$ select unnest(array['a1000000-0000-4000-8000-0000000000a1', 'a2000000-0000-4000-8000-0000000000a2']::uuid[]) $$,
  'admin A reads Client Brain rows of its own clients only');
select is_empty($$ select client_id from public.brand_profiles where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.audiences where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.offers where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.regions where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.sources where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.facts where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.decisions where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.insights where client_id = 'b1000000-0000-4000-8000-0000000000b1'
     union all select client_id from public.rules where client_id = 'b1000000-0000-4000-8000-0000000000b1' $$,
  'filtering by client B1 returns nothing to admin A (filters never expand access)');
select is_empty($$ select 1 from public.effective_rules('b1000000-0000-4000-8000-0000000000b1') $$,
  'effective_rules of client B1 is empty for admin A');
select is_empty($$ select 1 from public.rule_conflicts('b1000000-0000-4000-8000-0000000000b1') $$,
  'rule_conflicts of client B1 is empty for admin A');
select throws_ok($$ select public.create_source('b1000000-0000-4000-8000-0000000000b1', 'document', 'Intrusão', 'FIRST_PARTY') $$,
  'P0002', 'not found', 'admin A cannot register a source on client B1');
select throws_ok($$ select public.save_brand_profile('b1000000-0000-4000-8000-0000000000b1', 'x', 'x', 'x', '{}'::text[]) $$,
  'P0002', 'not found', 'admin A cannot write the brand profile of client B1');
select throws_ok($$ select public.propose_fact('b1000000-0000-4000-8000-0000000000b1', current_setting('acc.src_b1')::uuid, 'Intrusão') $$,
  'P0002', 'not found', 'admin A cannot propose knowledge on client B1');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_b1')::uuid, 'Fonte roubada') $$,
  'P0002', 'not found', 'a source of workspace B cannot back knowledge of client A1');
select throws_ok($$ select public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a2')::uuid, 'MUST', 'x', 'Fonte vizinha') $$,
  'P0002', 'not found', 'a source of sibling client A2 cannot back a rule of client A1');
select throws_ok($$ select public.save_audience('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.aud_b1')::uuid, 'Sequestro', 'x') $$,
  'P0002', 'not found', 'admin A cannot overwrite an audience of client B1 by id');
select throws_ok($$ select public.archive_context_item('audience', current_setting('acc.aud_b1')::uuid) $$,
  'P0002', 'not found', 'admin A cannot archive an audience of client B1');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact_b1p')::uuid) $$,
  'P0002', 'not found', 'admin A cannot approve knowledge of client B1');
select throws_ok($$ select public.activate_rule(current_setting('acc.rule_b1p')::uuid) $$,
  'P0002', 'not found', 'admin A cannot activate a rule of client B1');
select throws_ok($$ select public.reject_rule(current_setting('acc.rule_b1p')::uuid) $$,
  'P0002', 'not found', 'admin A cannot reject a rule of client B1');
select throws_ok($$ select public.activate_rule('0d0d0d0d-0000-4000-8000-00000000dead') $$,
  'P0002', 'not found', 'a nonexistent rule id is not found');
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_eq($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, $$ select 'b1000000-0000-4000-8000-0000000000b1'::uuid $$,
  'admin B reads Client Brain rows of client B1 only');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') $$,
  'effective_rules of client A1 is empty for admin B');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact_a1p')::uuid) $$,
  'P0002', 'not found', 'admin B cannot approve knowledge of client A1');
select throws_ok($$ select public.activate_rule(current_setting('acc.rule_a1p')::uuid) $$,
  'P0002', 'not found', 'admin B cannot activate a rule of client A1');
reset role;

-- ===========================================================================
-- The Client Brain is internal-only in Increment 2 (decision 3)
-- ===========================================================================
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'a client admin reads no Client Brain row of its own client');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') $$,
  'a client admin gets no effective rules');
select is_empty($$ select 1 from public.rule_conflicts('a1000000-0000-4000-8000-0000000000a1') $$,
  'a client admin gets no rule conflicts');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Sugestão do cliente') $$,
  '42501', 'permission denied', 'a client admin cannot propose knowledge');
select throws_ok($$ select public.save_audience('a1000000-0000-4000-8000-0000000000a1', null, 'Público do cliente', 'x') $$,
  '42501', 'permission denied', 'a client admin cannot edit strategy context');
select throws_ok($$ select public.approve_knowledge('fact', current_setting('acc.fact_a1p')::uuid) $$,
  'P0002', 'not found', 'a client admin cannot approve internal knowledge it cannot see');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'a client approver reads no Client Brain row');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'a client viewer reads no Client Brain row');
reset role;
select pg_temp.login_as('cb000000-0000-4000-8000-000000000001');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'a client approver of B1 reads no Client Brain row');
reset role;

-- ===========================================================================
-- Internal boundary: contributor fail-closed (ADR 0002), outsiders, invited
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'a contributor without grants reads no Client Brain row');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Tentativa') $$,
  'P0002', 'not found', 'a contributor without grants cannot reach client A1');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000008');
select isnt_empty($$ select 1 from public.facts where client_id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  'an explicit workspace-wide client.view grant lets a contributor read the Client Brain (ADR 0002)');
select throws_ok($$ select public.propose_fact('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Tentativa') $$,
  '42501', 'permission denied', 'client.view alone does not allow proposing knowledge');
reset role;

select pg_temp.login_as('f0000000-0000-4000-8000-000000000001');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'a user without memberships reads no Client Brain row');
select throws_ok($$ select public.create_source('a1000000-0000-4000-8000-0000000000a1', 'document', 'x', 'FIRST_PARTY') $$,
  'P0002', 'not found', 'a user without memberships cannot write the Client Brain');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-00000000000a');
select is_empty($$ select client_id from public.brand_profiles
     union all select client_id from public.audiences
     union all select client_id from public.offers
     union all select client_id from public.regions
     union all select client_id from public.sources
     union all select client_id from public.facts
     union all select client_id from public.decisions
     union all select client_id from public.insights
     union all select client_id from public.rules $$, 'an invited (not yet active) admin reads no Client Brain row');
reset role;

-- ===========================================================================
-- Authentication and direct writes (docs/05 §1, Increment 1 error contract)
-- ===========================================================================
select pg_temp.login_anon();
select throws_ok($$ select 1 from public.rules $$, '42501', null, 'anon cannot read rules');
select throws_ok($$ select 1 from public.facts $$, '42501', null, 'anon cannot read facts');
select throws_ok($$ select public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'x', 'x') $$,
  '42501', null, 'anon cannot call the Client Brain API');
reset role;

select pg_temp.login_without_subject();
select throws_ok($$ select public.create_source('a1000000-0000-4000-8000-0000000000a1', 'document', 'x', 'FIRST_PARTY') $$,
  '42501', null, 'a token without subject cannot call the Client Brain API');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok(
  $$ insert into public.facts (client_id, source_id, statement, status)
     values ('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'Fato direto', 'active') $$,
  '42501', null, 'even an admin cannot insert active knowledge directly');
select throws_ok($$ update public.rules set status = 'active' where id = current_setting('acc.rule_a1p')::uuid $$,
  '42501', null, 'even an admin cannot activate a rule by UPDATE');
select throws_ok($$ update public.facts set status = 'active' where id = current_setting('acc.fact_a1p')::uuid $$,
  '42501', null, 'even an admin cannot approve a fact by UPDATE');
select throws_ok($$ update public.sources set trust_level = 'FIRST_PARTY' where id = current_setting('acc.src_a1_untrusted')::uuid $$,
  '42501', null, 'source trust cannot be raised by UPDATE');
select throws_ok($$ delete from public.rules where id = current_setting('acc.rule_a1')::uuid $$,
  '42501', null, 'rules cannot be deleted directly');
select throws_ok($$ delete from public.audiences where id = current_setting('acc.aud_a1')::uuid $$,
  '42501', null, 'context items cannot be deleted directly');
reset role;

select is_empty(
  $$ select t from unnest(array['brand_profiles', 'audiences', 'offers', 'regions', 'sources', 'facts', 'decisions', 'insights', 'rules']) t
      where has_table_privilege('authenticated', 'public.' || t, 'INSERT, UPDATE, DELETE, TRUNCATE')
         or has_table_privilege('anon', 'public.' || t, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE') $$,
  'no Client Brain table is writable by authenticated or reachable by anon');
select is_empty(
  $$ select t from unnest(array['brand_profiles', 'audiences', 'offers', 'regions', 'sources', 'facts', 'decisions', 'insights', 'rules']) t
      where not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) $$,
  'row level security is enabled on every Client Brain table');

-- Workspace B data is untouched by everything above.
select is((select status::text from public.rules where id = current_setting('acc.rule_b1')::uuid), 'active',
  'the active rule of client B1 is unchanged');
select is((select status::text from public.facts where id = current_setting('acc.fact_b1p')::uuid), 'proposed',
  'the proposed fact of client B1 is unchanged');
select is((select count(*)::integer from public.audiences where client_id = 'b1000000-0000-4000-8000-0000000000b1'), 1,
  'the audiences of client B1 are unchanged');

select * from finish();
rollback;
