-- Increment 7 / Portal boundary: what clients see on the calendar, tenant isolation, no direct writes
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-7/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

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

create function pg_temp.claims(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
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
  ('a0000000-0000-4000-8000-000000000002'::uuid, 'a_planner@acc.test'),
  ('a0000000-0000-4000-8000-000000000003'::uuid, 'a_account@acc.test'),
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a_creative@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000002'::uuid, 'a1_approver@acc.test'),
  ('c1000000-0000-4000-8000-000000000005'::uuid, 'a1_viewer@acc.test'),
  ('c2000000-0000-4000-8000-000000000001'::uuid, 'a2_viewer@acc.test'),
  ('c2000000-0000-4000-8000-000000000002'::uuid, 'a2_approver@acc.test'),
  ('cb000000-0000-4000-8000-000000000001'::uuid, 'b1_approver@acc.test')
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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000002', 'strategist', '{publication.schedule}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000003', 'account', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000005', 'creative', '{}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'approver', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000005', 'viewer', '{}', 'active'),
  ('a2000000-0000-4000-8000-0000000000a2', 'c2000000-0000-4000-8000-000000000001', 'viewer', '{}', 'active'),
  ('a2000000-0000-4000-8000-0000000000a2', 'c2000000-0000-4000-8000-000000000002', 'approver', '{}', 'active'),
  ('b1000000-0000-4000-8000-0000000000b1', 'cb000000-0000-4000-8000-000000000001', 'approver', '{}', 'active');

-- Internally approved content through the Increment 2 and 5 APIs (no hard rules: nothing blocks).
-- The helpers run as the session owner with the caller's identity in the JWT claims: the API
-- functions still check that identity's capabilities.
create function pg_temp.approved_content(p_client uuid, p_title text) returns void
language plpgsql as $$
declare
  v_aud uuid := public.save_audience(p_client, null, 'Público ' || p_title, 'x');
  v_pauta uuid := public.create_pauta(p_client, 'Pauta ' || p_title);
  v_content uuid;
  v_rev uuid;
begin
  perform public.update_pauta(v_pauta, jsonb_build_object('objective', 'o',
    'audience_ids', jsonb_build_array(v_aud), 'message', 'm', 'cta', 'c'));
  perform public.mark_pauta_ready(v_pauta);
  v_content := public.create_content(v_pauta, 'instagram', 'post', p_title);
  perform public.save_content_payload(v_content, jsonb_build_object('body', 'Texto de ' || p_title));
  v_rev := public.submit_for_internal_review(v_content);
  perform public.complete_internal_review(v_rev, 'approve');
  perform set_config('acc.content_' || lower(p_title), v_content::text, true);
  perform set_config('acc.rev_' || lower(p_title), v_rev::text, true);
end;
$$;

-- Internally approved, then approved by the client through the Increment 6 API.
create function pg_temp.client_approved(p_client uuid, p_title text, p_admin uuid, p_approver uuid)
returns void language plpgsql as $$
declare
  v_request uuid;
begin
  perform pg_temp.claims(p_admin);
  perform pg_temp.approved_content(p_client, p_title);
  v_request := public.request_client_approval(current_setting('acc.rev_' || lower(p_title))::uuid);
  perform pg_temp.claims(p_approver);
  perform public.decide_approval(v_request, 'approve');
end;
$$;

select pg_temp.client_approved('a1000000-0000-4000-8000-0000000000a1', 'A1',
  'a0000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000002');
select pg_temp.client_approved('a1000000-0000-4000-8000-0000000000a1', 'Extra',
  'a0000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000002');
select pg_temp.client_approved('a2000000-0000-4000-8000-0000000000a2', 'A2',
  'a0000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000002');
select pg_temp.client_approved('b1000000-0000-4000-8000-0000000000b1', 'B1',
  'b0000000-0000-4000-8000-000000000001', 'cb000000-0000-4000-8000-000000000001');

-- Pend: approved internally only, waiting for the client with a due date.
select pg_temp.claims('a0000000-0000-4000-8000-000000000001');
select pg_temp.approved_content('a1000000-0000-4000-8000-0000000000a1', 'Pend');
select set_config('acc.req_pend', public.request_client_approval(
  current_setting('acc.rev_pend')::uuid, now() + interval '3 days')::text, true);
select set_config('acc.meeting', public.create_meeting(
  'a1000000-0000-4000-8000-0000000000a1', 'Reunião mensal', now() + interval '1 day')::text, true);
select set_config('acc.pub_a2', public.schedule_publication(
  current_setting('acc.content_a2')::uuid, now() + interval '2 days')::text, true);
select pg_temp.claims('b0000000-0000-4000-8000-000000000001');
select set_config('acc.pub_b1', public.schedule_publication(
  current_setting('acc.content_b1')::uuid, now() + interval '2 days')::text, true);

-- A1: scheduled by the planner; the creative sets its production deadline.
select pg_temp.claims('a0000000-0000-4000-8000-000000000002');
select set_config('acc.pub_a1', public.schedule_publication(
  current_setting('acc.content_a1')::uuid, now() + interval '2 days')::text, true);
select set_config('acc.deadline', (date_trunc('minute', now()) + interval '1 day')::text, true);
select pg_temp.claims('a0000000-0000-4000-8000-000000000005');
select public.set_production_deadline(current_setting('acc.content_a1')::uuid,
  current_setting('acc.deadline')::timestamptz);
select set_config('request.jwt.claims', '', true);

-- ===========================================================================
-- What the client sees (docs/00 §3.2, docs/01, docs/11 invariant 9)
-- ===========================================================================
select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select set_eq($$ select id from public.publications $$,
  $$ select current_setting('acc.pub_a1')::uuid $$,
  'a client member sees the publications of its own client only');
select set_eq($$ select distinct event_type from public.calendar_events(now(), now() + interval '30 days') $$,
  $$ values ('publication'), ('approval_deadline') $$,
  'the portal calendar shows publications and approval deadlines, never internal dates');
select set_eq($$ select entity_id from public.calendar_events(now(), now() + interval '30 days') $$,
  $$ values (current_setting('acc.pub_a1')::uuid), (current_setting('acc.req_pend')::uuid) $$,
  'the portal calendar lists exactly the client''s publication and open approval');
select throws_ok($$ select public.schedule_publication(current_setting('acc.content_extra')::uuid, now() + interval '5 days') $$,
  'P0002', 'not found', 'a client member cannot schedule');
reset role;

select pg_temp.login_as('c2000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.publications $$,
  $$ select current_setting('acc.pub_a2')::uuid $$,
  'a member of sibling client A2 sees only A2 publications');
select is_empty($$ select 1 from public.calendar_events(now(), now() + interval '30 days')
                    where client_id <> 'a2000000-0000-4000-8000-0000000000a2' $$,
  'the A2 calendar shows nothing of A1');
select throws_ok($$ select * from public.calendar_events(now(), now() + interval '30 days', 'a1000000-0000-4000-8000-0000000000a1') $$,
  'P0002', 'not found', 'asking for another client''s calendar is not found');
reset role;

-- Tenant isolation ----------------------------------------------------------------
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.publications $$,
  $$ select current_setting('acc.pub_b1')::uuid $$,
  'admin B sees only workspace B publications');
select is_empty($$ select 1 from public.calendar_events(now(), now() + interval '30 days')
                    where client_id <> 'b1000000-0000-4000-8000-0000000000b1' $$,
  'admin B''s calendar shows nothing of workspace A');
select throws_ok($$ select public.schedule_publication(current_setting('acc.content_extra')::uuid, now() + interval '5 days') $$,
  'P0002', 'not found', 'admin B cannot schedule workspace A content');
select throws_ok($$ select public.reschedule_publication(current_setting('acc.pub_a1')::uuid, now() + interval '5 days') $$,
  'P0002', 'not found', 'admin B cannot move a workspace A publication');
select throws_ok($$ select public.set_production_deadline(current_setting('acc.content_a1')::uuid, now() + interval '5 days') $$,
  'P0002', 'not found', 'admin B cannot set a workspace A deadline');
reset role;

-- Internal staff see every typed date of their clients --------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select set_eq($$ select distinct event_type from public.calendar_events(now(), now() + interval '30 days', 'a1000000-0000-4000-8000-0000000000a1') $$,
  $$ values ('publication'), ('production_deadline'), ('approval_deadline'), ('meeting') $$,
  'the internal calendar shows every typed date of the client');
reset role;

-- No direct writes ---------------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ update public.publications set scheduled_at = now() where id = current_setting('acc.pub_a1')::uuid $$,
  '42501', null, 'publications cannot be updated directly, even by an admin');
reset role;
select pg_temp.login_anon();
select throws_ok($$ select 1 from public.publications $$, '42501', null, 'anon reads nothing');
select throws_ok($$ select * from public.calendar_events(now(), now() + interval '30 days') $$,
  '42501', null, 'anon cannot call the calendar API');
reset role;
select is_empty(
  $$ select t from unnest(array['publications']) t
      where has_table_privilege('authenticated', 'public.' || t, 'INSERT, UPDATE, DELETE, TRUNCATE')
         or has_table_privilege('anon', 'public.' || t, 'SELECT')
         or not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) $$,
  'publications have RLS, no API write privileges and no anon access');

select * from finish();
rollback;
