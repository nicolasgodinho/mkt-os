-- Increment 5 / Initiatives, opportunities, pautas and the Definition of Ready
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-5/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

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
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a_account@acc.test'),
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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000003', 'account', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000005', 'creative', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000007', 'contributor', '{}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'approver', '{}', 'active');

-- Client Brain context through the Increment 2 API (admin holds every capability).
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.src_a1', public.create_source('a1000000-0000-4000-8000-0000000000a1',
  'meeting', 'Kickoff A1', 'FIRST_PARTY')::text, true);
select set_config('acc.aud_a1', public.save_audience('a1000000-0000-4000-8000-0000000000a1', null,
  'Famílias', 'Pais com filhos')::text, true);
select set_config('acc.offer_a1', public.save_offer('a1000000-0000-4000-8000-0000000000a1', null,
  'Avaliação', 'Primeira consulta', null, null)::text, true);
select set_config('acc.src_a2', public.create_source('a2000000-0000-4000-8000-0000000000a2',
  'document', 'Briefing A2', 'FIRST_PARTY')::text, true);
select set_config('acc.aud_a2', public.save_audience('a2000000-0000-4000-8000-0000000000a2', null,
  'Público A2', 'x')::text, true);
-- Rules of A1: client-wide MUST cta and MUST_NOT preco, a soft PREFER, an Instagram-only MUST_NOT.
select set_config('acc.r_cta', public.propose_rule('a1000000-0000-4000-8000-0000000000a1',
  current_setting('acc.src_a1')::uuid, 'MUST', 'cta', 'Todo post tem CTA')::text, true);
select set_config('acc.r_preco', public.propose_rule('a1000000-0000-4000-8000-0000000000a1',
  current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'preco', 'Nunca citar preço')::text, true);
select set_config('acc.r_soft', public.propose_rule('a1000000-0000-4000-8000-0000000000a1',
  current_setting('acc.src_a1')::uuid, 'PREFER', null, 'Prefira frases curtas')::text, true);
select set_config('acc.r_ig', public.propose_rule('a1000000-0000-4000-8000-0000000000a1',
  current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'emoji', 'Sem emojis no Instagram', 'instagram')::text, true);
select public.activate_rule(current_setting('acc.r_cta')::uuid);
select public.activate_rule(current_setting('acc.r_preco')::uuid);
select public.activate_rule(current_setting('acc.r_soft')::uuid);
select public.activate_rule(current_setting('acc.r_ig')::uuid);
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_config('acc.src_b1', public.create_source('b1000000-0000-4000-8000-0000000000b1',
  'document', 'Briefing B1', 'FIRST_PARTY')::text, true);
select set_config('acc.pauta_b1', public.create_pauta('b1000000-0000-4000-8000-0000000000b1',
  'Pauta secreta B1')::text, true);
reset role;

-- ===========================================================================
-- Initiatives (docs/02 Initiative, docs/04 Initiative) — strategy.edit
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.init', (public.create_initiative('a1000000-0000-4000-8000-0000000000a1', 'campaign', 'Clareamento de verão', '2026-12-01', '2027-02-28'))::text, true);
select is((select row(kind, status, client_id = 'a1000000-0000-4000-8000-0000000000a1')::text from public.initiatives where id = current_setting('acc.init')::uuid),
  '(campaign,draft,t)', 'a new initiative starts as draft');
select throws_ok($$ select public.create_initiative('a1000000-0000-4000-8000-0000000000a1', 'campaign', 'x', '2027-01-01', '2026-01-01') $$,
  '22023', null, 'an initiative cannot end before it starts');
select lives_ok($$ select public.set_initiative_status(current_setting('acc.init')::uuid, 'planning') $$, 'draft -> planning');
select lives_ok($$ select public.set_initiative_status(current_setting('acc.init')::uuid, 'production') $$, 'planning -> production');
select throws_ok($$ select public.set_initiative_status(current_setting('acc.init')::uuid, 'completed') $$,
  '22023', null, 'production cannot jump to completed');
select lives_ok($$ select public.set_initiative_status(current_setting('acc.init')::uuid, 'paused') $$, 'production -> paused');
select lives_ok($$ select public.set_initiative_status(current_setting('acc.init')::uuid, 'canceled') $$, 'paused -> canceled');
select throws_ok($$ select public.set_initiative_status(current_setting('acc.init')::uuid, 'planning') $$,
  '22023', null, 'canceled is terminal');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.create_initiative('a1000000-0000-4000-8000-0000000000a1', 'always_on', 'x') $$,
  '42501', 'permission denied', 'initiatives require strategy.edit');
reset role;

-- ===========================================================================
-- Opportunities (docs/04 Opportunity): DETECTED -> WATCHING | DISMISSED | CONVERTED
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.opp', (public.create_opportunity('a1000000-0000-4000-8000-0000000000a1', 'seasonal', 'Verão', 'Procura por clareamento sobe em dezembro',
  null, 0.7, '2026-12-31', array[current_setting('acc.src_a1')::uuid]))::text, true);
select is((select status::text from public.opportunities where id = current_setting('acc.opp')::uuid), 'detected',
  'a new opportunity is detected, not yet an editorial commitment');
select lives_ok($$ select public.review_opportunity(current_setting('acc.opp')::uuid, 'watch') $$, 'an opportunity can be watched');
select set_config('acc.from_opp', (public.convert_opportunity(current_setting('acc.opp')::uuid))::text, true);
select is(
  (select row(p.opportunity_id = current_setting('acc.opp')::uuid, p.status, p.title, o.status)::text
     from public.pautas p join public.opportunities o on o.id = p.opportunity_id
    where p.id = current_setting('acc.from_opp')::uuid),
  '(t,draft,Verão,converted)',
  'converting creates a draft pauta linked to the opportunity');
select throws_ok($$ select public.convert_opportunity(current_setting('acc.opp')::uuid) $$,
  '22023', null, 'an opportunity is converted at most once');
select set_config('acc.opp2', (public.create_opportunity('a1000000-0000-4000-8000-0000000000a1', 'trend', 'Tendência', 'x'))::text, true);
select lives_ok($$ select public.review_opportunity(current_setting('acc.opp2')::uuid, 'dismiss') $$, 'an opportunity can be dismissed');
select throws_ok($$ select public.convert_opportunity(current_setting('acc.opp2')::uuid) $$,
  '22023', null, 'a dismissed opportunity cannot be converted');
select throws_ok($$ select public.review_opportunity(current_setting('acc.opp2')::uuid, 'promote') $$,
  '22023', null, 'unknown review decisions are rejected');
reset role;

-- ===========================================================================
-- Pautas and the Definition of Ready (docs/04 Content: READY requires DoR; docs/07 §7)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.pauta', (public.create_pauta('a1000000-0000-4000-8000-0000000000a1', 'Campanha de clareamento', current_setting('acc.init')::uuid))::text, true);
select set_eq($$ select field from public.pauta_readiness(current_setting('acc.pauta')::uuid) where not ok $$,
  array['objective', 'audience', 'message_or_angle', 'cta'],
  'an empty pauta misses every Definition of Ready item');
select throws_ok($$ select public.mark_pauta_ready(current_setting('acc.pauta')::uuid) $$,
  '22023', null, 'a pauta cannot be ready without its Definition of Ready');
select throws_ok($$ select public.update_pauta(current_setting('acc.pauta')::uuid, '{"budget": 1000}'::jsonb) $$,
  '22023', null, 'unknown pauta fields are rejected');
select lives_ok($$ select public.update_pauta(current_setting('acc.pauta')::uuid, jsonb_build_object(
  'objective', 'Gerar agendamentos', 'audience_ids', jsonb_build_array(current_setting('acc.aud_a1')::uuid),
  'angle', 'Segurança do clareamento profissional', 'cta', 'Agende sua avaliação',
  'offer_id', current_setting('acc.offer_a1')::uuid, 'source_ids', jsonb_build_array(current_setting('acc.src_a1')::uuid),
  'mandatories', 'Citar o dentista responsável', 'constraints', 'Sem antes e depois')) $$,
  'the strategist fills the pauta');
select is_empty($$ select 1 from public.pauta_readiness(current_setting('acc.pauta')::uuid) where not ok $$,
  'the Definition of Ready is met');
select lives_ok($$ select public.mark_pauta_ready(current_setting('acc.pauta')::uuid) $$, 'the pauta becomes ready');
select is((select status::text from public.pautas where id = current_setting('acc.pauta')::uuid), 'ready', 'status ready');
select lives_ok($$ select public.update_pauta(current_setting('acc.pauta')::uuid, '{"cta": "  "}'::jsonb) $$,
  'a ready pauta can still be edited');
select is((select status::text from public.pautas where id = current_setting('acc.pauta')::uuid), 'draft',
  'an edit that breaks the Definition of Ready returns the pauta to draft');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.update_pauta(current_setting('acc.pauta')::uuid, '{"cta": "x"}'::jsonb) $$,
  '42501', 'permission denied', 'pautas require strategy.edit');
reset role;
select isnt_empty(
  $$ select 1 from public.audit_logs where actor_id = 'a0000000-0000-4000-8000-000000000004' and target_id = current_setting('acc.pauta')::uuid $$,
  'pauta changes are audited');

select * from finish();
rollback;
