-- Increment 2 / Rules: activation, supersession, conflict, resolution
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-2/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(59);

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
-- Rules: proposal, activation, supersession, conflict, resolution
-- (docs/02 §3-§6, docs/04 Rule, docs/05 §2 and §6, docs/11)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', null, 'Sem assunto') $$,
  '22023', null, 'a hard rule requires a subject');
select throws_ok($$ select public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', '  ', 'Assunto vazio') $$,
  '22023', null, 'a hard rule rejects a blank subject');
select set_config('acc.soft', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'PREFER', null, 'Prefira frases curtas'))::text, true);
select is((select status::text from public.rules where id = current_setting('acc.soft')::uuid), 'proposed',
  'a soft rule may omit the subject');
select set_config('acc.cta', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'cta', 'Todo post tem CTA'))::text, true);
select throws_ok(
  $$ select public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'x', 'Janela invertida',
                                null, 50, '2027-01-01', '2026-01-01') $$,
  '22023', null, 'a rule cannot end before it starts');
select throws_ok($$ select public.activate_rule(current_setting('acc.cta')::uuid) $$,
  '42501', 'permission denied', 'a strategist cannot activate a rule (rule.activate)');
select throws_ok($$ select public.reject_rule(current_setting('acc.cta')::uuid) $$,
  '42501', 'permission denied', 'a strategist cannot reject a rule');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-00000000000b');
select throws_ok($$ select public.activate_rule(current_setting('acc.cta')::uuid) $$,
  '42501', 'permission denied', 'knowledge.approve does not allow activating rules');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.activate_rule(current_setting('acc.cta')::uuid) $$,
  'P0002', 'not found', 'a client Approver cannot activate a Rule (docs/11 required negative)');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.activate_rule(current_setting('acc.cta')::uuid) $$,
  'P0002', 'not found', 'approval.decide on a client does not allow activating rules');
reset role;

-- Activation ------------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select is(public.activate_rule(current_setting('acc.cta')::uuid)::text, 'active', 'a holder of rule.activate activates a rule');
select is((select approved_by from public.rules where id = current_setting('acc.cta')::uuid), 'a0000000-0000-4000-8000-000000000001'::uuid,
  'the activator is recorded on the rule');
select throws_ok($$ select public.activate_rule(current_setting('acc.cta')::uuid) $$,
  '22023', null, 'an active rule cannot be activated again');
select is(public.activate_rule(current_setting('acc.soft')::uuid)::text, 'active', 'soft rules are activated the same way');
select set_config('acc.pending', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'pendente', 'Ainda em análise'))::text, true);
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') $$,
  $$ select unnest(array[current_setting('acc.cta')::uuid, current_setting('acc.soft')::uuid]) $$,
  'only active rules are effective (proposed rules are not)');
select throws_ok($$ select public.reject_rule(current_setting('acc.cta')::uuid) $$,
  '22023', null, 'an active rule is retired by supersession, not rejection (docs/04)');

-- Untrusted sources cannot become rules (decision 4) ---------------------------
select set_config('acc.untrusted', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1_untrusted')::uuid, 'MUST_NOT', 'preco', 'Nunca mostrar preço'))::text, true);
select throws_ok($$ select public.activate_rule(current_setting('acc.untrusted')::uuid) $$,
  '22023', null, 'a rule backed by an UNTRUSTED_EXTERNAL source cannot be activated');
select is((select status::text from public.rules where id = current_setting('acc.untrusted')::uuid), 'proposed',
  'the untrusted rule stays proposed');

-- Supersession ------------------------------------------------------------------
select set_config('acc.cta2', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'cta', 'Todo post tem CTA com link',
  null, 50, null, null, current_setting('acc.cta')::uuid))::text, true);
select is(public.activate_rule(current_setting('acc.cta2')::uuid)::text, 'active', 'a superseding rule is activated');
select is((select status::text from public.rules where id = current_setting('acc.cta')::uuid), 'superseded',
  'activation atomically supersedes the previous rule');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') $$,
  $$ select unnest(array[current_setting('acc.cta2')::uuid, current_setting('acc.soft')::uuid]) $$,
  'the superseded rule leaves the effective set');
select throws_ok($$ select public.activate_rule(current_setting('acc.cta')::uuid) $$,
  '22023', null, 'a superseded rule can never be activated again');
select ok((select count(*) from public.audit_logs where target_id = current_setting('acc.cta')::uuid and actor_id = 'a0000000-0000-4000-8000-000000000001') >= 2,
  'activation and supersession of the rule are both audited (docs/05 §6)');
select throws_ok(
  $$ select public.propose_rule('a2000000-0000-4000-8000-0000000000a2', current_setting('acc.src_a2')::uuid, 'MUST', 'cta', 'x', null, 50, null, null, current_setting('acc.cta2')::uuid) $$,
  'P0002', 'not found', 'a rule cannot supersede a rule of another client');

select set_config('acc.emoji', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'emoji', 'Use emojis'))::text, true);
select public.activate_rule(current_setting('acc.emoji')::uuid);
select set_config('acc.emoji2', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'emoji', 'Não use emojis',
  null, 50, null, null, current_setting('acc.emoji')::uuid))::text, true);
select is(public.activate_rule(current_setting('acc.emoji2')::uuid)::text, 'active',
  'superseding with the opposite polarity is not a conflict');

-- Conflict (decision 1) -------------------------------------------------------------
select set_config('acc.hash_must', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'hashtag', 'Use hashtags'))::text, true);
select public.activate_rule(current_setting('acc.hash_must')::uuid);
select set_config('acc.hash_not', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'hashtag', 'Nunca use hashtags'))::text, true);
select is(public.activate_rule(current_setting('acc.hash_not')::uuid)::text, 'conflict',
  'opposite hard rules on the same subject, scope and priority conflict');
select is((select status::text from public.rules where id = current_setting('acc.hash_must')::uuid), 'conflict',
  'the previously active rule is also in conflict');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where subject = 'hashtag' $$,
  'conflicting rules leave the effective set (no automatic winner)');
select set_eq($$ select id from public.rule_conflicts('a1000000-0000-4000-8000-0000000000a1') $$,
  $$ select unnest(array[current_setting('acc.hash_must')::uuid, current_setting('acc.hash_not')::uuid]) $$,
  'rule_conflicts lists both sides of the conflict');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_eq($$ select id from public.rule_conflicts('a1000000-0000-4000-8000-0000000000a1') $$,
  $$ select unnest(array[current_setting('acc.hash_must')::uuid, current_setting('acc.hash_not')::uuid]) $$,
  'internal staff see the conflict');
select isnt_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where id = current_setting('acc.cta2')::uuid $$,
  'internal staff read the effective rules');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') $$,
  'a client approver reads no effective rule (internal-only)');
select is_empty($$ select 1 from public.rule_conflicts('a1000000-0000-4000-8000-0000000000a1') $$,
  'a client approver reads no rule conflict');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select lives_ok($$ select public.reject_rule(current_setting('acc.hash_not')::uuid) $$,
  'a human resolves the conflict by rejecting one side');
select is((select status::text from public.rules where id = current_setting('acc.hash_must')::uuid), 'active',
  'the remaining rule returns to active');
select isnt_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where id = current_setting('acc.hash_must')::uuid $$,
  'the remaining rule is effective again');
select is_empty($$ select 1 from public.rule_conflicts('a1000000-0000-4000-8000-0000000000a1') $$,
  'no conflict remains');
select throws_ok($$ select public.activate_rule(current_setting('acc.hash_not')::uuid) $$,
  '22023', null, 'a rejected rule can never be activated again');
select isnt_empty(
  $$ select 1 from public.audit_logs where target_id = current_setting('acc.hash_not')::uuid and actor_id = 'a0000000-0000-4000-8000-000000000001' $$,
  'the rejection is audited');

select set_config('acc.link_must', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'link', 'Sempre inclua link'))::text, true);
select public.activate_rule(current_setting('acc.link_must')::uuid);
select set_config('acc.link_not', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'link', 'Nunca inclua link'))::text, true);
select public.activate_rule(current_setting('acc.link_not')::uuid);
select set_config('acc.link_not2', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'link', 'Link só na bio',
  null, 50, null, null, current_setting('acc.link_must')::uuid))::text, true);
select is(public.activate_rule(current_setting('acc.link_not2')::uuid)::text, 'active',
  'a human resolves a conflict by superseding one side');
select is((select status::text from public.rules where id = current_setting('acc.link_must')::uuid), 'superseded',
  'the superseded side leaves the conflict');
select is((select status::text from public.rules where id = current_setting('acc.link_not')::uuid), 'active',
  'the other side returns to active');

-- Resolution: priority, scope specificity, validity (docs/02 §4 and §6) ---------
select set_config('acc.font_must', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'fonte', 'Use a fonte da marca', null, 80))::text, true);
select set_config('acc.font_not', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'fonte', 'Não use a fonte da marca', null, 40))::text, true);
select is(public.activate_rule(current_setting('acc.font_must')::uuid)::text, 'active', 'higher-priority rule activates');
select is(public.activate_rule(current_setting('acc.font_not')::uuid)::text, 'active',
  'opposite rules with different priorities do not conflict');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where subject = 'fonte' $$,
  $$ select current_setting('acc.font_must')::uuid::uuid $$,
  'at the same scope the higher priority wins');

select set_config('acc.slang_client', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'girias', 'Sem gírias'))::text, true);
select set_config('acc.slang_ig', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'girias', 'Gírias no Instagram', 'instagram'))::text, true);
select is(public.activate_rule(current_setting('acc.slang_client')::uuid)::text, 'active', 'client-scoped rule activates');
select is(public.activate_rule(current_setting('acc.slang_ig')::uuid)::text, 'active',
  'a channel rule does not conflict with a client rule');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1', 'instagram') where subject = 'girias' $$,
  $$ select current_setting('acc.slang_ig')::uuid::uuid $$,
  'the narrower channel scope wins on its channel');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1', 'linkedin') where subject = 'girias' $$,
  $$ select current_setting('acc.slang_client')::uuid::uuid $$,
  'other channels keep the client rule');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where subject = 'girias' $$,
  $$ select current_setting('acc.slang_client')::uuid::uuid $$,
  'without a channel only client-scoped rules apply');
select isnt_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1', 'instagram') where id = current_setting('acc.cta2')::uuid $$,
  'client rules without a channel override still apply on the channel');

select set_config('acc.promo_must', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'promo', 'Anuncie a promoção',
  null, 50, '2030-01-01', '2030-06-30'))::text, true);
select set_config('acc.promo_not', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'promo', 'Promoção encerrada',
  null, 50, '2030-07-01', null))::text, true);
select is(public.activate_rule(current_setting('acc.promo_must')::uuid)::text, 'active', 'a future rule can be activated');
select is(public.activate_rule(current_setting('acc.promo_not')::uuid)::text, 'active',
  'opposite rules with disjoint validity windows do not conflict');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1', null, '2030-03-01') where subject = 'promo' $$,
  $$ select current_setting('acc.promo_must')::uuid::uuid $$,
  'inside its window the first rule is effective');
select set_eq($$ select id from public.effective_rules('a1000000-0000-4000-8000-0000000000a1', null, '2030-08-01') where subject = 'promo' $$,
  $$ select current_setting('acc.promo_not')::uuid::uuid $$,
  'after the first window the second rule is effective');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1', null, '2029-12-01') where subject = 'promo' $$,
  'rules are not effective before their window starts');

select set_config('acc.frete_must', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST', 'frete', 'Frete grátis no texto',
  null, 50, '2030-01-01', '2030-12-31'))::text, true);
select public.activate_rule(current_setting('acc.frete_must')::uuid);
select set_config('acc.frete_not', (public.propose_rule('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.src_a1')::uuid, 'MUST_NOT', 'frete', 'Não prometa frete',
  null, 50, '2030-06-01', null))::text, true);
select is(public.activate_rule(current_setting('acc.frete_not')::uuid)::text, 'conflict',
  'overlapping validity windows conflict');

select set_config('acc.a2_cta', (public.propose_rule('a2000000-0000-4000-8000-0000000000a2', current_setting('acc.src_a2')::uuid, 'MUST_NOT', 'cta', 'Sem CTA para A2'))::text, true);
select is(public.activate_rule(current_setting('acc.a2_cta')::uuid)::text, 'active',
  'rules of different clients never conflict');
select is_empty($$ select 1 from public.effective_rules('a1000000-0000-4000-8000-0000000000a1') where id = current_setting('acc.a2_cta')::uuid $$,
  'rules of another client never enter the effective set');
reset role;

select is((select status::text from public.rules where id = current_setting('acc.pending')::uuid), 'proposed',
  'nothing above activated the pending rule');

select * from finish();
rollback;
