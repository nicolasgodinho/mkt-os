-- Increment 6 / Comments and threads with internal and client visibility
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-6/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

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

-- ===========================================================================
-- Comments and threads (docs/10 threads/comments; visibility internal | client)
-- ===========================================================================
select pg_temp.login_as('c1000000-0000-4000-8000-000000000003');
select set_config('acc.c1', (public.add_comment('content', current_setting('acc.content_a1')::uuid, 'Gostei do texto.'))::text, true);
select is((select row(t.visibility, t.target_id = current_setting('acc.content_a1')::uuid, c.author_id = 'c1000000-0000-4000-8000-000000000003')::text
             from public.comments c join public.threads t on t.id = c.thread_id where c.id = current_setting('acc.c1')::uuid),
  '(client,t,t)', 'a client collaborator comments in the client-visible thread');
select throws_ok($$ select public.add_comment('content', current_setting('acc.content_a1')::uuid, 'interno?', 'internal') $$,
  '42501', 'permission denied', 'client roles cannot write internal comments');
select throws_ok($$ select public.add_comment('content', current_setting('acc.content_extra')::uuid, 'x') $$,
  'P0002', 'not found', 'a client cannot comment on content that was not shared with it');
select throws_ok($$ select public.add_comment('content', current_setting('acc.content_a1')::uuid, '   ') $$,
  '22023', null, 'a blank comment is rejected');
select throws_ok($$ select public.add_comment('pauta', current_setting('acc.content_a1')::uuid, 'x') $$,
  '22023', null, 'unknown comment targets are rejected');
reset role;

select pg_temp.login_as('c1000000-0000-4000-8000-000000000005');
select throws_ok($$ select public.add_comment('content', current_setting('acc.content_a1')::uuid, 'x') $$,
  '42501', 'permission denied', 'a viewer is read-only');
select isnt_empty($$ select 1 from public.comments where id = current_setting('acc.c1')::uuid $$,
  'a viewer reads client-visible comments');
reset role;

select pg_temp.login_as('a0000000-0000-4000-8000-000000000005');
select set_config('acc.internal', (public.add_comment('content', current_setting('acc.content_extra')::uuid, 'Revisar a legenda.', 'internal'))::text, true);
select set_config('acc.reply', (public.add_comment('content', current_setting('acc.content_a1')::uuid, 'Obrigado! Ajustamos.', 'client'))::text, true);
select is((select count(distinct thread_id)::integer from public.comments where id in (current_setting('acc.c1')::uuid, current_setting('acc.reply')::uuid)), 1,
  'client-visible comments on one content share one thread');
reset role;
select pg_temp.login_as('c1000000-0000-4000-8000-000000000001');
select is_empty($$ select 1 from public.comments where id = current_setting('acc.internal')::uuid $$,
  'a client admin never sees internal comments');
select is_empty($$ select 1 from public.threads where visibility = 'internal' $$,
  'a client admin never sees internal threads');
reset role;

select * from finish();
rollback;
