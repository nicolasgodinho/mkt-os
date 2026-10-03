-- Increment 7 / Typed calendar projection and date semantics
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-7/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

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
-- Calendar semantics (docs/06 "Calendar model", docs/11 invariant 7)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000002');
select public.reschedule_publication(current_setting('acc.pub_a1')::uuid, now() + interval '4 days');
reset role;
select is((select production_due_at from public.contents where id = current_setting('acc.content_a1')::uuid),
  current_setting('acc.deadline')::timestamptz,
  'moving the publication date never changes the production deadline');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select public.set_production_deadline(current_setting('acc.content_a1')::uuid, now() + interval '3 days');
reset role;
select results_eq(
  $$ select (select production_due_at from public.contents where id = current_setting('acc.content_a1')::uuid),
            (select scheduled_at from public.publications where id = current_setting('acc.pub_a1')::uuid) $$,
  $$ values (now() + interval '3 days', now() + interval '4 days') $$,
  'moving the production deadline never changes the publication date');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.set_production_deadline(current_setting('acc.content_a1')::uuid, now() + interval '2 days') $$,
  '42501', 'permission denied', 'setting a production deadline needs content.edit');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.set_production_deadline(current_setting('acc.content_a1')::uuid, now() + interval '2 days') $$,
  'P0002', 'not found', 'clients cannot set production deadlines');
reset role;

-- The typed projection -----------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select set_eq(
  $$ select event_type, entity_id, date_field
       from public.calendar_events(now(), now() + interval '30 days', 'a1000000-0000-4000-8000-0000000000a1') $$,
  $$ values ('publication', current_setting('acc.pub_a1')::uuid, 'scheduled_at'),
            ('production_deadline', current_setting('acc.content_a1')::uuid, 'production_due_at'),
            ('approval_deadline', current_setting('acc.req_pend')::uuid, 'due_at'),
            ('meeting', current_setting('acc.meeting')::uuid, 'starts_at') $$,
  'each event names the one date field a move would change');
select results_eq(
  $$ select starts_at, title, content_id, status
       from public.calendar_events(now(), now() + interval '30 days', 'a1000000-0000-4000-8000-0000000000a1')
      where event_type = 'publication' $$,
  $$ values (now() + interval '4 days', 'A1', current_setting('acc.content_a1')::uuid, 'scheduled') $$,
  'a publication event carries its date, content title, content and status');
select set_eq($$ select distinct client_id from public.calendar_events(now(), now() + interval '30 days') $$,
  $$ values ('a1000000-0000-4000-8000-0000000000a1'::uuid), ('a2000000-0000-4000-8000-0000000000a2'::uuid) $$,
  'without a client filter the calendar covers every client the caller can see');
select is_empty($$ select 1 from public.calendar_events(now() + interval '10 days', now() + interval '20 days',
                                                        'a1000000-0000-4000-8000-0000000000a1') $$,
  'events outside the range are left out');
select throws_ok($$ select * from public.calendar_events(now(), now()) $$,
  '22023', 'invalid calendar range', 'an empty range is refused');
select throws_ok($$ select * from public.calendar_events(now(), now() + interval '101 days') $$,
  '22023', 'invalid calendar range', 'a range longer than 100 days is refused');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.cancel_publication(current_setting('acc.pub_a2')::uuid);
select is_empty($$ select 1 from public.calendar_events(now(), now() + interval '30 days', 'a2000000-0000-4000-8000-0000000000a2')
                    where event_type = 'publication' $$,
  'canceled publications leave the calendar');
select public.mark_publication_published(current_setting('acc.pub_a1')::uuid, null);
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select is((select status from public.calendar_events(now(), now() + interval '30 days')
            where event_type = 'publication'), 'published',
  'the client sees a published publication as published');
reset role;

select * from finish();
rollback;
