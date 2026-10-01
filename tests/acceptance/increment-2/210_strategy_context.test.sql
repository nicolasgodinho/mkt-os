-- Increment 2 / Strategy context: brand profile, audiences, offers, regions
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-2/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

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
-- Strategy context: Brand, Audience, Offer, Region (docs/07 §4, docs/10)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000004');
select lives_ok(
  $$ select public.save_brand_profile('a1000000-0000-4000-8000-0000000000a1', 'Clínica odontológica', 'Acolhedora',
                                      'Próxima e técnica', array['https://example.test/moodboard']) $$,
  'a strategist (strategy.edit) saves the brand profile');
select lives_ok(
  $$ select public.save_brand_profile('a1000000-0000-4000-8000-0000000000a1', 'Clínica odontológica', 'Acolhedora e moderna',
                                      'Próxima e técnica', '{}'::text[]) $$,
  'saving the brand profile again updates it');
select is((select count(*)::integer from public.brand_profiles where client_id = 'a1000000-0000-4000-8000-0000000000a1'), 1,
  'a client has exactly one brand profile');

select set_config('acc.aud', (public.save_audience('a1000000-0000-4000-8000-0000000000a1', null, 'Famílias', 'Pais com filhos pequenos'))::text, true);
select isnt_empty($$ select 1 from public.audiences where id = current_setting('acc.aud')::uuid and client_id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  'save_audience without id creates an audience of the client');
select lives_ok($$ select public.save_audience('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.aud')::uuid, 'Famílias jovens', 'Pais de 25 a 35') $$,
  'save_audience with id updates the audience');
select is((select name from public.audiences where id = current_setting('acc.aud')::uuid), 'Famílias jovens',
  'the update is persisted');
select is((select count(*)::integer from public.audiences where client_id = 'a1000000-0000-4000-8000-0000000000a1'), 1,
  'updating does not create a second audience');
select throws_ok($$ select public.save_audience('a2000000-0000-4000-8000-0000000000a2', current_setting('acc.aud')::uuid, 'Mover', 'x') $$,
  'P0002', 'not found', 'an audience cannot be addressed through another client');
select throws_ok($$ select public.save_audience('a1000000-0000-4000-8000-0000000000a1', null, '   ', 'x') $$,
  '22023', null, 'a blank name is rejected');

select set_config('acc.offer', (public.save_offer('a1000000-0000-4000-8000-0000000000a1', null, 'Plano anual', 'Manutenção', '2026-01-01', '2026-12-31'))::text, true);
select isnt_empty($$ select 1 from public.offers where id = current_setting('acc.offer')::uuid and client_id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  'save_offer creates an offer with a validity window (docs/02 §6)');
select throws_ok(
  $$ select public.save_offer('a1000000-0000-4000-8000-0000000000a1', null, 'Oferta invertida', 'x', '2026-12-31', '2026-01-01') $$,
  '22023', null, 'an offer cannot end before it starts');

select set_config('acc.region', (public.save_region('a1000000-0000-4000-8000-0000000000a1', null, 'Sul', 'RS, SC e PR'))::text, true);
select isnt_empty($$ select 1 from public.regions where id = current_setting('acc.region')::uuid and client_id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  'save_region creates a region');

select lives_ok($$ select public.archive_context_item('audience', current_setting('acc.aud')::uuid) $$,
  'a strategist archives an audience (soft delete, docs/05 §7)');
select is((select status::text from public.audiences where id = current_setting('acc.aud')::uuid), 'archived',
  'the archived audience is kept with status archived');
select throws_ok($$ select public.archive_context_item('fact', current_setting('acc.offer')::uuid) $$,
  '22023', null, 'archive_context_item only accepts audience, offer or region');
select throws_ok($$ select public.archive_context_item('region', '0d0d0d0d-0000-4000-8000-00000000dead') $$,
  'P0002', 'not found', 'archiving a nonexistent item is not found');
reset role;

-- Roles without strategy.edit ------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select isnt_empty($$ select 1 from public.offers where id = current_setting('acc.offer')::uuid $$,
  'a creative (client.view) reads the strategy context');
select throws_ok($$ select public.save_audience('a1000000-0000-4000-8000-0000000000a1', null, 'Público', 'x') $$,
  '42501', 'permission denied', 'a creative cannot create audiences');
select throws_ok($$ select public.save_brand_profile('a1000000-0000-4000-8000-0000000000a1', 'x', 'x', 'x', '{}'::text[]) $$,
  '42501', 'permission denied', 'a creative cannot edit the brand profile');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000006');
select throws_ok($$ select public.save_region('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.region')::uuid, 'Sul e Sudeste', 'x') $$,
  '42501', 'permission denied', 'an analyst cannot edit regions');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.save_offer('a1000000-0000-4000-8000-0000000000a1', current_setting('acc.offer')::uuid, 'Desconto', 'x', null, null) $$,
  '42501', 'permission denied', 'an account manager cannot edit offers');
select throws_ok($$ select public.archive_context_item('offer', current_setting('acc.offer')::uuid) $$,
  '42501', 'permission denied', 'an account manager cannot archive offers');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.save_brand_profile('a1000000-0000-4000-8000-0000000000a1', 'x', 'x', 'x', '{}'::text[]) $$,
  '42501', 'permission denied', 'a client admin cannot edit the internal brand profile');
select throws_ok($$ select public.archive_context_item('region', current_setting('acc.region')::uuid) $$,
  'P0002', 'not found', 'a client admin cannot reach internal context items');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000007');
select throws_ok($$ select public.save_audience('a1000000-0000-4000-8000-0000000000a1', null, 'Público', 'x') $$,
  'P0002', 'not found', 'a contributor without grants cannot reach client A1');
reset role;

select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.save_region('a1000000-0000-4000-8000-0000000000a1', null, 'Invasão', 'x') $$,
  'P0002', 'not found', 'admin B cannot create context for client A1');
select throws_ok($$ select public.archive_context_item('offer', current_setting('acc.offer')::uuid) $$,
  'P0002', 'not found', 'admin B cannot archive an offer of client A1');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select ok(public.save_region('a2000000-0000-4000-8000-0000000000a2', null, 'Nordeste', 'Capitais') is not null,
  'an admin holds strategy.edit');
reset role;

select is((select status::text from public.offers where id = current_setting('acc.offer')::uuid), 'active',
  'denied attempts left the offer active');

select * from finish();
rollback;
