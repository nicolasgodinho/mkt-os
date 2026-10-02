-- Increment 6 / Portal boundary: what clients see, tenant isolation, no direct writes
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

select pg_temp.login_as('a0000000-0000-4000-8000-000000000003');
select set_config('acc.req', (public.request_client_approval(current_setting('acc.rev_a1')::uuid, '2026-12-01'))::text, true);
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.internal_note', (public.add_comment('content', current_setting('acc.content_a1')::uuid, 'Nota interna: cliente costuma pedir ajustes.', 'internal'))::text, true);
select set_config('acc.client_note', (public.add_comment('content', current_setting('acc.content_a1')::uuid, 'Pode aprovar até sexta?', 'client'))::text, true);
reset role;

-- ===========================================================================
-- What the client sees (docs/00 §3.2, docs/01, docs/11 invariant 9)
-- ===========================================================================
select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select set_eq($$ select id from public.approval_requests $$, $$ select current_setting('acc.req')::uuid::uuid $$,
  'a client member sees the approval requests of its own client only');
select set_eq($$ select id from public.content_revisions $$, $$ select current_setting('acc.rev_a1')::uuid::uuid $$,
  'a client member sees exactly the revision sent for approval, never other revisions');
select is_empty($$ select 1 from public.contents $$,
  'working content (drafts, internal status) stays internal');
select set_eq($$ select body from public.comments $$, $$ select 'Pode aprovar até sexta?'::text $$,
  'internal-only comments are never visible to client roles');
select is((select count(*)::integer from public.portal_approvals('a1000000-0000-4000-8000-0000000000a1')), 1,
  'portal_approvals lists the client''s requests');
select is_empty($$ select 1 from public.portal_approvals('b1000000-0000-4000-8000-0000000000b1') $$,
  'portal_approvals of another client is empty');
reset role;

select pg_temp.login_as('c2000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.approval_requests
                   union all select 1 from public.content_revisions
                   union all select 1 from public.comments $$,
  'a member of sibling client A2 sees nothing of A1');
reset role;
select pg_temp.login_as('cb000000-0000-4000-8000-000000000001');
select set_eq($$ select id from public.approval_requests $$, $$ select current_setting('acc.req_b1')::uuid::uuid $$,
  'a B1 approver sees only B1 requests');
select throws_ok($$ select public.decide_approval(current_setting('acc.req')::uuid, 'approve') $$,
  'P0002', 'not found', 'a B1 approver cannot decide an A1 request');
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.approval_requests where client_id <> 'b1000000-0000-4000-8000-0000000000b1'
                   union all select 1 from public.comments where client_id <> 'b1000000-0000-4000-8000-0000000000b1' $$,
  'admin B sees nothing of workspace A');
select throws_ok($$ select public.add_comment('content', current_setting('acc.content_a1')::uuid, 'intrusão', 'client') $$,
  'P0002', 'not found', 'admin B cannot comment on content of workspace A');
select throws_ok($$ select public.request_client_approval(current_setting('acc.rev_a1')::uuid) $$,
  'P0002', 'not found', 'admin B cannot request approval for workspace A');
reset role;

-- Internal staff see both visibilities ---------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select set_eq($$ select id from public.comments where client_id = 'a1000000-0000-4000-8000-0000000000a1' $$,
  $$ select unnest(array[current_setting('acc.internal_note')::uuid, current_setting('acc.client_note')::uuid]) $$,
  'internal staff see internal and client comments');
reset role;

-- No direct writes -------------------------------------------------------------------
select pg_temp.login_as('c1000000-0000-4000-8000-000000000002');
select throws_ok($$ update public.approval_requests set status = 'approved' where id = current_setting('acc.req')::uuid $$,
  '42501', null, 'a client cannot approve by UPDATE');
select throws_ok(
  $$ insert into public.comments (thread_id, client_id, author_id, body)
     select thread_id, client_id, 'c1000000-0000-4000-8000-000000000002', 'forjado' from public.comments limit 1 $$,
  '42501', null, 'comments cannot be inserted directly');
reset role;
select pg_temp.login_anon();
select throws_ok($$ select 1 from public.approval_requests $$, '42501', null, 'anon reads nothing');
select throws_ok($$ select public.portal_approvals('a1000000-0000-4000-8000-0000000000a1') $$, '42501', null, 'anon cannot call the portal API');
reset role;
select is_empty(
  $$ select t from unnest(array['approval_requests', 'approval_decisions', 'threads', 'comments']) t
      where has_table_privilege('authenticated', 'public.' || t, 'INSERT, UPDATE, DELETE, TRUNCATE')
         or has_table_privilege('anon', 'public.' || t, 'SELECT')
         or not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || t)::regclass) $$,
  'collaboration tables have RLS, no API write privileges and no anon access');

select * from finish();
rollback;
