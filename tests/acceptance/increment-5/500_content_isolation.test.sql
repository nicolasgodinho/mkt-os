-- Increment 5 / Planning and content isolation, internal-only, immutable revisions
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-5/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

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
select set_config('acc.init', (public.create_initiative('a1000000-0000-4000-8000-0000000000a1', 'campaign', 'Clareamento de verão'))::text, true);
select set_config('acc.opp', (public.create_opportunity('a1000000-0000-4000-8000-0000000000a1', 'seasonal', 'Verão', 'Procura sobe em dezembro'))::text, true);
select set_config('acc.content', (public.create_content(current_setting('acc.pauta')::uuid, 'instagram', 'post', 'Post clareamento'))::text, true);
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select public.save_content_payload(current_setting('acc.content')::uuid, '{"body": "Agende sua avaliação."}'::jsonb);
select set_config('acc.rev', (public.submit_for_internal_review(current_setting('acc.content')::uuid))::text, true);
reset role;

-- ===========================================================================
-- Isolation (docs/05 §1, docs/11 invariants 1 and 9)
-- ===========================================================================
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.pautas where client_id <> 'b1000000-0000-4000-8000-0000000000b1'
                   union all select 1 from public.contents
                   union all select 1 from public.content_revisions
                   union all select 1 from public.initiatives
                   union all select 1 from public.opportunities $$,
  'admin B reads no planning or content data of workspace A');
select throws_ok($$ select public.update_pauta(current_setting('acc.pauta')::uuid, '{"objective": "x"}'::jsonb) $$,
  'P0002', 'not found', 'admin B cannot edit a pauta of workspace A');
select throws_ok($$ select public.create_content(current_setting('acc.pauta')::uuid, 'instagram', 'post', 'x') $$,
  'P0002', 'not found', 'admin B cannot create content from a pauta of workspace A');
select throws_ok($$ select public.save_content_payload(current_setting('acc.content')::uuid, '{"body": "x"}'::jsonb) $$,
  'P0002', 'not found', 'admin B cannot edit content of workspace A');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev')::uuid, 'approve') $$,
  'P0002', 'not found', 'admin B cannot review a revision of workspace A');
select throws_ok($$ select public.create_initiative('a1000000-0000-4000-8000-0000000000a1', 'campaign', 'x') $$,
  'P0002', 'not found', 'admin B cannot create initiatives for client A1');
select is_empty($$ select 1 from public.revision_validation(current_setting('acc.rev')::uuid) $$,
  'admin B gets no validation rows for a revision of workspace A');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.update_pauta(current_setting('acc.pauta_b1')::uuid, '{"objective": "x"}'::jsonb) $$,
  'P0002', 'not found', 'admin A cannot edit a pauta of workspace B');
select throws_ok(
  $$ select public.update_pauta(current_setting('acc.pauta')::uuid, jsonb_build_object('audience_ids', jsonb_build_array(current_setting('acc.aud_a2')::uuid))) $$,
  'P0002', 'not found', 'a pauta cannot reference an audience of another client');
select throws_ok(
  $$ select public.create_opportunity('a1000000-0000-4000-8000-0000000000a1', 'x', 'x', 'x', null, null, null, array[current_setting('acc.src_b1')::uuid]) $$,
  'P0002', 'not found', 'an opportunity cannot cite evidence of another tenant');
select throws_ok($$ select public.record_rule_check(current_setting('acc.rev')::uuid, '0d0d0d0d-0000-4000-8000-00000000dead', 'pass') $$,
  'P0002', 'not found', 'a rule check needs a rule of the same client');
reset role;

-- Internal-only (client review arrives with Increment 6) ---------------------------------
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.initiatives
     union all select 1 from public.opportunities
     union all select 1 from public.pautas
     union all select 1 from public.contents
     union all select 1 from public.content_revisions
     union all select 1 from public.content_rule_checks $$, 'a client admin reads no planning or content data in Increment 5');
select throws_ok($$ select public.create_pauta('a1000000-0000-4000-8000-0000000000a1', 'Pauta do cliente') $$,
  '42501', 'permission denied', 'a client admin cannot create pautas');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select is_empty($$ select 1 from public.initiatives
     union all select 1 from public.opportunities
     union all select 1 from public.pautas
     union all select 1 from public.contents
     union all select 1 from public.content_revisions
     union all select 1 from public.content_rule_checks $$, 'a client approver reads no internal content data');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev')::uuid, 'approve') $$,
  'P0002', 'not found', 'a client approver cannot perform an internal review');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select is_empty($$ select 1 from public.initiatives
     union all select 1 from public.opportunities
     union all select 1 from public.pautas
     union all select 1 from public.contents
     union all select 1 from public.content_revisions
     union all select 1 from public.content_rule_checks $$, 'a contributor without grants reads nothing (ADR 0002)');
reset role;
select pg_temp.login_anon();
select throws_ok($$ select 1 from public.contents $$, '42501', null, 'anon cannot read contents');
reset role;

-- No direct writes; revisions are immutable even for the owner ------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ update public.contents set status = 'approved' where id = current_setting('acc.content')::uuid $$,
  '42501', null, 'content status cannot be changed by UPDATE');
select throws_ok($$ update public.pautas set status = 'ready' where id = current_setting('acc.pauta')::uuid $$,
  '42501', null, 'pauta status cannot be changed by UPDATE');
select throws_ok(
  $$ insert into public.content_rule_checks (revision_id, rule_id, result) values (current_setting('acc.rev')::uuid, current_setting('acc.r_preco')::uuid, 'pass') $$,
  '42501', null, 'rule checks cannot be inserted directly');
reset role;
select throws_ok($$ update public.content_revisions set payload = '{"body": "adulterado"}' where id = current_setting('acc.rev')::uuid $$,
  null, null, 'a content revision cannot be updated, not even by the database owner (BLOCKER)');
select throws_ok($$ delete from public.content_revisions where id = current_setting('acc.rev')::uuid $$,
  null, null, 'a content revision cannot be deleted, not even by the database owner');
select is_empty(
  $$ select t from unnest(array['initiatives', 'opportunities', 'pautas', 'contents', 'content_revisions', 'content_rule_checks']) t
      where has_table_privilege('authenticated', 'public.' || t, 'INSERT, UPDATE, DELETE, TRUNCATE')
         or has_table_privilege('anon', 'public.' || t, 'SELECT')
         or not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) $$,
  'content tables have RLS, no API write privileges and no anon access');

select * from finish();
rollback;
