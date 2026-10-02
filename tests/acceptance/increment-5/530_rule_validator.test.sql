-- Increment 5 / Rule validator: hard rules, MUST_NOT violations and conflicts block
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-5/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

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

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.pauta', (public.create_pauta('a1000000-0000-4000-8000-0000000000a1', 'Campanha de clareamento'))::text, true);
select public.update_pauta(current_setting('acc.pauta')::uuid, jsonb_build_object(
  'objective', 'Gerar agendamentos', 'audience_ids', jsonb_build_array(current_setting('acc.aud_a1')::uuid),
  'message', 'Sorriso mais branco com segurança', 'cta', 'Agende sua avaliação',
  'offer_id', current_setting('acc.offer_a1')::uuid, 'source_ids', jsonb_build_array(current_setting('acc.src_a1')::uuid)));
select public.mark_pauta_ready(current_setting('acc.pauta')::uuid);
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.ig', (public.create_content(current_setting('acc.pauta')::uuid, 'instagram', 'post', 'Post Instagram'))::text, true);
select set_config('acc.li', (public.create_content(current_setting('acc.pauta')::uuid, 'linkedin', 'post', 'Post LinkedIn'))::text, true);
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select public.save_content_payload(current_setting('acc.ig')::uuid, '{"body": "Clareamento por R$ 99!"}'::jsonb);
select set_config('acc.rev', (public.submit_for_internal_review(current_setting('acc.ig')::uuid))::text, true);
select public.save_content_payload(current_setting('acc.li')::uuid, '{"body": "Agende sua avaliação."}'::jsonb);
select set_config('acc.li_rev', (public.submit_for_internal_review(current_setting('acc.li')::uuid))::text, true);
reset role;

-- ===========================================================================
-- The rule validator (docs/11 invariant 3: a MUST_NOT violation cannot pass)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select set_eq($$ select rule_id from public.revision_validation(current_setting('acc.rev')::uuid) $$,
  $$ select unnest(array[current_setting('acc.r_cta')::uuid, current_setting('acc.r_preco')::uuid, current_setting('acc.r_ig')::uuid]) $$,
  'an Instagram revision is validated against client-wide and Instagram hard rules');
select set_eq($$ select rule_id from public.revision_validation(current_setting('acc.li_rev')::uuid) $$,
  $$ select unnest(array[current_setting('acc.r_cta')::uuid, current_setting('acc.r_preco')::uuid]) $$,
  'a LinkedIn revision ignores Instagram-only rules; soft rules never block');
select is((select count(*)::integer from public.revision_validation(current_setting('acc.rev')::uuid) where blocking), 3,
  'every unchecked hard rule blocks');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev')::uuid, 'approve') $$,
  '22023', null, 'a revision with unchecked hard rules cannot be approved');

select lives_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, current_setting('acc.r_cta')::uuid, 'pass') $$,
  'a reviewer records that the CTA rule is met');
select lives_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, current_setting('acc.r_ig')::uuid, 'not_applicable', 'Sem emojis no texto') $$,
  'a rule can be marked not applicable with a note');
select lives_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, current_setting('acc.r_preco')::uuid, 'violation', 'Cita preço') $$,
  'a reviewer records a MUST_NOT violation');
select is((select row(result, blocking)::text from public.revision_validation(current_setting('acc.rev')::uuid) where rule_id = current_setting('acc.r_preco')::uuid),
  '(violation,t)', 'the violation blocks');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev')::uuid, 'approve') $$,
  '22023', null, 'a revision violating a MUST_NOT rule can never be approved');
select lives_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, current_setting('acc.r_preco')::uuid, 'pass') $$,
  'a check can be updated after a second look');
select is((select count(*)::integer from public.revision_validation(current_setting('acc.rev')::uuid) where blocking), 0,
  'nothing blocks any more');
select throws_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, current_setting('acc.r_soft')::uuid, 'pass') $$,
  '22023', null, 'only effective hard rules of the revision are checked');
reset role;

-- An open rule conflict blocks approval (docs/07 §12: conflicts block automated flows) -----
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.r_conflict', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'preco', 'Sempre cite o preço'))::text, true);
select is(public.activate_rule(current_setting('acc.r_conflict')::uuid)::text, 'conflict', 'setup: a conflict on "preco"');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select ok((select bool_or(blocking) from public.revision_validation(current_setting('acc.rev')::uuid)
            where rule_id in (current_setting('acc.r_preco')::uuid, current_setting('acc.r_conflict')::uuid)),
  'conflicting rules are listed and block');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev')::uuid, 'approve') $$,
  '22023', null, 'a revision cannot be approved while a relevant rule conflict is open');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.reject_rule(current_setting('acc.r_conflict')::uuid);
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select lives_ok($$ select public.complete_internal_review(current_setting('acc.rev')::uuid, 'approve') $$,
  'once the conflict is resolved and every hard rule is checked, the revision is approved');
select throws_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, current_setting('acc.r_cta')::uuid, 'violation') $$,
  '22023', null, 'checks are recorded only while the revision is under internal review');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.record_rule_check(current_setting('acc.li_rev')::uuid, current_setting('acc.r_cta')::uuid, 'pass') $$,
  '42501', 'permission denied', 'recording checks requires content.review_internal');
reset role;
select isnt_empty(
  $$ select 1 from public.audit_logs where actor_id = 'a0000000-0000-4000-8000-000000000005' and target_id = current_setting('acc.rev')::uuid $$,
  'rule checks and the approval are audited on the revision');

select * from finish();
rollback;
