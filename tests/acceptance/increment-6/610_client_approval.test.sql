-- Increment 6 / Client approval of an exact revision: request, decide, changes, cancel
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-6/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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
  ('a0000000-0000-4000-8000-000000000005'::uuid, 'a_creative@acc.test'),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test'),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test'),
  ('c1000000-0000-4000-8000-000000000002'::uuid, 'a1_approver@acc.test'),
  ('c1000000-0000-4000-8000-000000000003'::uuid, 'a1_collab@acc.test'),
  ('c1000000-0000-4000-8000-000000000004'::uuid, 'a1_collab_appr@acc.test'),
  ('c1000000-0000-4000-8000-000000000005'::uuid, 'a1_viewer@acc.test'),
  ('c2000000-0000-4000-8000-000000000001'::uuid, 'a2_viewer@acc.test'),
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
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000003', 'account', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000005', 'creative', '{}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000002', 'approver', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000003', 'collaborator', '{}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000004', 'collaborator', '{approval.decide}', 'active'),
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000005', 'viewer', '{}', 'active'),
  ('a2000000-0000-4000-8000-0000000000a2', 'c2000000-0000-4000-8000-000000000001', 'viewer', '{}', 'active'),
  ('b1000000-0000-4000-8000-0000000000b1', 'cb000000-0000-4000-8000-000000000001', 'approver', '{}', 'active');

-- Internally approved content through the Increment 2 and 5 APIs (no hard rules: nothing blocks).
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

-- The helper runs as the session owner with the caller's identity in the JWT claims: the API
-- functions still check that identity's capabilities.
select set_config('request.jwt.claims', json_build_object('sub', 'a0000000-0000-4000-8000-000000000001',
  'role', 'authenticated')::text, true);
select pg_temp.approved_content('a1000000-0000-4000-8000-0000000000a1', 'A1');
select pg_temp.approved_content('a1000000-0000-4000-8000-0000000000a1', 'Extra');
select pg_temp.approved_content('a2000000-0000-4000-8000-0000000000a2', 'A2');
select set_config('request.jwt.claims', json_build_object('sub', 'b0000000-0000-4000-8000-000000000001',
  'role', 'authenticated')::text, true);
select pg_temp.approved_content('b1000000-0000-4000-8000-0000000000b1', 'B1');
select set_config('acc.req_b1', public.request_client_approval(current_setting('acc.rev_b1')::uuid)::text, true);

-- ===========================================================================
-- Requesting client approval (approval.request; docs/04 ApprovalRequest)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.request_client_approval(current_setting('acc.rev_a1')::uuid) $$,
  '42501', 'permission denied', 'requesting client approval requires approval.request');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select set_config('acc.req', (public.request_client_approval(current_setting('acc.rev_a1')::uuid, '2026-12-01'))::text, true);
select is(
  (select row(r.status, r.revision_id = current_setting('acc.rev_a1')::uuid, r.content_id = current_setting('acc.content_a1')::uuid, r.requested_by = 'a0000000-0000-4000-8000-000000000003',
              c.status)::text
     from public.approval_requests r join public.contents c on c.id = r.content_id where r.id = current_setting('acc.req')::uuid),
  '(requested,t,t,t,client_review)',
  'the request targets the exact revision and the content moves to client review');
select throws_ok($$ select public.request_client_approval(current_setting('acc.rev_a1')::uuid) $$,
  '22023', null, 'a content has at most one open approval request');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.draft_pauta', (public.create_pauta('a1000000-0000-4000-8000-0000000000a1', 'Pauta rascunho'))::text, true);
select public.update_pauta(current_setting('acc.draft_pauta')::uuid, jsonb_build_object('objective', 'o',
  'audience_ids', jsonb_build_array((select id from public.audiences where client_id = 'a1000000-0000-4000-8000-0000000000a1' limit 1)),
  'message', 'm', 'cta', 'c'));
select public.mark_pauta_ready(current_setting('acc.draft_pauta')::uuid);
select set_config('acc.wip', (public.create_content(current_setting('acc.draft_pauta')::uuid, 'instagram', 'post', 'Em revisão interna'))::text, true);
select public.save_content_payload(current_setting('acc.wip')::uuid, '{"body": "x"}'::jsonb);
select set_config('acc.wip_rev', (public.submit_for_internal_review(current_setting('acc.wip')::uuid))::text, true);
select throws_ok($$ select public.request_client_approval(current_setting('acc.wip_rev')::uuid) $$,
  '22023', null, 'only an internally approved revision can go to the client');
reset role;

-- ===========================================================================
-- Deciding (client-side approval.decide only)
-- ===========================================================================
select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'approve') $$,
  '42501', 'permission denied', 'a viewer cannot decide');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000003');
select throws_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'approve') $$,
  '42501', 'permission denied', 'a collaborator cannot decide without an explicit grant');
reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'approve') $$,
  '42501', 'permission denied', 'internal staff can never approve on behalf of the client');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'publish') $$,
  '22023', null, 'unknown decisions are rejected');
select lives_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'approve', 'Pode publicar.') $$,
  'the client approver approves');
reset role;
-- Checked as the owner: working content stays internal, so the client cannot read contents.
select is(
  (select row(r.status, c.status, c.client_approved_revision_id = current_setting('acc.rev_a1')::uuid)::text
     from public.approval_requests r join public.contents c on c.id = r.content_id where r.id = current_setting('acc.req')::uuid),
  '(approved,approved,t)', 'the content is client-approved AT that revision');
select is(
  (select row(d.decision, d.approver_user_id = 'c1000000-0000-4000-8000-000000000002', d.comment)::text
     from public.approval_decisions d where d.approval_request_id = current_setting('acc.req')::uuid),
  '(approve,t,"Pode publicar.")', 'the decision is recorded immutably with its comment');
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'changes') $$,
  '22023', null, 'a decided request cannot be decided again');
reset role;

select isnt_empty(
  $$ select 1 from public.audit_logs
      where client_id = 'a1000000-0000-4000-8000-0000000000a1' and actor_id = 'c1000000-0000-4000-8000-000000000002' and target_id = current_setting('acc.req')::uuid $$,
  'the client decision is audited (docs/05 §6)');

-- Requesting changes and the explicit grant ------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select set_config('acc.req2', (public.request_client_approval(current_setting('acc.rev_extra')::uuid))::text, true);
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000004');
select lives_ok($$ select public.decide_approval(current_setting('acc.req2')::uuid, 'changes', 'Trocar a foto.') $$,
  'a collaborator with an explicit approval.decide grant can decide');
reset role;
select is(
  (select row(r.status, c.status, c.client_approved_revision_id)::text
     from public.approval_requests r join public.contents c on c.id = r.content_id where r.id = current_setting('acc.req2')::uuid),
  '(changes_requested,producing,)', 'requesting changes sends the content back to production');

-- Canceling --------------------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.req_a2', (public.request_client_approval(current_setting('acc.rev_a2')::uuid))::text, true);
select lives_ok($$ select public.cancel_approval_request(current_setting('acc.req_a2')::uuid) $$, 'internal staff can cancel a request');
select is(
  (select row(r.status, c.status)::text
     from public.approval_requests r join public.contents c on c.id = r.content_id where r.id = current_setting('acc.req_a2')::uuid),
  '(canceled,approved)', 'a canceled request returns the content to internally approved');
reset role;
select pg_temp.login_as('c2000000-0000-4000-8000-000000000001');
select is((select status::text from public.portal_approvals('a2000000-0000-4000-8000-0000000000a2') where request_id = current_setting('acc.req_a2')::uuid),
  'canceled', 'the client sees the request as canceled');
reset role;

select * from finish();
rollback;
