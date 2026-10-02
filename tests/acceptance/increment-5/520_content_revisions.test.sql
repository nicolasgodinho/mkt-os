-- Increment 5 / Content, immutable revisions, internal approval at a revision
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-5/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

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

-- ===========================================================================
-- Content and immutable revisions (docs/02 ContentRevision — BLOCKER; docs/04 Content)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.create_content(current_setting('acc.pauta')::uuid, 'instagram', 'post', 'x') $$,
  '42501', 'permission denied', 'creating content requires content.create');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select set_config('acc.draft_pauta', (public.create_pauta('a1000000-0000-4000-8000-0000000000a1', 'Pauta sem DoR'))::text, true);
select throws_ok($$ select public.create_content(current_setting('acc.draft_pauta')::uuid, 'instagram', 'post', 'x') $$,
  '22023', null, 'content can only execute a ready pauta');
select set_config('acc.content', (public.create_content(current_setting('acc.pauta')::uuid, 'instagram', 'post', 'Post clareamento'))::text, true);
select is((select row(status, channel, pauta_id = current_setting('acc.pauta')::uuid, current_revision_id)::text
             from public.contents where id = current_setting('acc.content')::uuid),
  '(ready,instagram,t,)', 'new content starts ready, on its channel, without revisions');
select throws_ok($$ select public.save_content_payload(current_setting('acc.content')::uuid, '{"body": "x"}'::jsonb) $$,
  '42501', 'permission denied', 'a strategist creates content but does not edit it (content.edit)');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.submit_for_internal_review(current_setting('acc.content')::uuid) $$,
  '22023', null, 'content without a body cannot be submitted');
select lives_ok($$ select public.save_content_payload(current_setting('acc.content')::uuid,
  '{"headline": "Sorriso branco", "body": "Clareamento com segurança. Agende sua avaliação.", "hashtags": ["#sorriso"]}'::jsonb) $$,
  'a creative edits the working payload');
select is((select status::text from public.contents where id = current_setting('acc.content')::uuid), 'producing',
  'editing moves the content to producing');
select throws_ok($$ select public.save_content_payload(current_setting('acc.content')::uuid, '{"body": "x", "script": "<b>"}'::jsonb) $$,
  '22023', null, 'unknown payload fields are rejected');
select set_config('acc.rev1', (public.submit_for_internal_review(current_setting('acc.content')::uuid))::text, true);
select is(
  (select row(r.revision_number, r.payload ->> 'headline', r.immutable_hash is not null,
              c.status, c.current_revision_id = r.id)::text
     from public.content_revisions r join public.contents c on c.id = r.content_id
    where r.id = current_setting('acc.rev1')::uuid),
  '(1,"Sorriso branco",t,internal_review,t)',
  'submitting snapshots the payload into revision 1 and starts internal review');
reset role;

-- Approval targets the revision (all hard rules checked; see 530 for the validator) ----------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select public.record_rule_check(current_setting('acc.rev1')::uuid, current_setting('acc.r_cta')::uuid, 'pass');
select public.record_rule_check(current_setting('acc.rev1')::uuid, current_setting('acc.r_preco')::uuid, 'pass');
select public.record_rule_check(current_setting('acc.rev1')::uuid, current_setting('acc.r_ig')::uuid, 'pass');
select lives_ok($$ select public.complete_internal_review(current_setting('acc.rev1')::uuid, 'approve') $$,
  'an internal reviewer (content.review_internal) approves revision 1');
select is((select row(status, approved_revision_id = current_setting('acc.rev1')::uuid)::text from public.contents where id = current_setting('acc.content')::uuid),
  '(approved,t)', 'the content is approved AT revision 1');

-- A material edit after approval never touches the approved revision (docs/11 invariant 2) -----
select lives_ok($$ select public.save_content_payload(current_setting('acc.content')::uuid,
  '{"headline": "Sorriso branco", "body": "Texto novo depois da aprovação."}'::jsonb) $$,
  'the working payload can still be edited after approval');
select is((select row(status, approved_revision_id = current_setting('acc.rev1')::uuid)::text from public.contents where id = current_setting('acc.content')::uuid),
  '(producing,t)', 'an edit after approval returns the content to producing; revision 1 stays the approved one');
select is((select payload ->> 'body' from public.content_revisions where id = current_setting('acc.rev1')::uuid),
  'Clareamento com segurança. Agende sua avaliação.',
  'the approved revision payload never changes');
select set_config('acc.rev2', (public.submit_for_internal_review(current_setting('acc.content')::uuid))::text, true);
select is((select revision_number from public.content_revisions where id = current_setting('acc.rev2')::uuid), 2,
  'resubmitting creates revision 2');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev1')::uuid, 'approve') $$,
  '22023', null, 'only the current revision can be reviewed');
select lives_ok($$ select public.complete_internal_review(current_setting('acc.rev2')::uuid, 'changes') $$,
  'the reviewer can request changes');
select is((select row(status, approved_revision_id = current_setting('acc.rev1')::uuid)::text from public.contents where id = current_setting('acc.content')::uuid),
  '(producing,t)', 'requesting changes returns the content to producing');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select throws_ok($$ select public.complete_internal_review(current_setting('acc.rev2')::uuid, 'approve') $$,
  '42501', 'permission denied', 'internal review requires content.review_internal');
reset role;
select isnt_empty(
  $$ select 1 from public.audit_logs
      where client_id = 'a1000000-0000-4000-8000-0000000000a1' and actor_id = 'a0000000-0000-4000-8000-000000000005' and target_id = current_setting('acc.rev1')::uuid $$,
  'the internal approval of a revision is audited');

select * from finish();
rollback;
