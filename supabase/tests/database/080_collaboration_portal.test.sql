-- Builder tests for Increment 6 (ExecPlan 0006): decisions the protected TEST_SPEC does not freeze —
-- decision immutability, audit action names, internal portal preview, helper privileges.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e6000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'collab-admin@builder.test', now(), now()),
  ('e6000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'collab-client@builder.test', now(), now());
insert into public.users (id, display_name) values
  ('e6000000-0000-4000-8000-000000000001', 'collab-admin'),
  ('e6000000-0000-4000-8000-000000000002', 'collab-client') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e6000000-0000-4000-8000-00000000aaaa', 'Builder Collab', 'builder-collab');
insert into public.clients (id, workspace_id, name, slug) values
  ('e6100000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-00000000aaaa', 'Collab C1', 'collab-c1');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e6000000-0000-4000-8000-00000000aaaa', 'e6000000-0000-4000-8000-000000000001', 'admin', 'active');
insert into public.client_memberships (client_id, user_id, role, status) values
  ('e6100000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002', 'approver', 'active');

select pg_temp.login_as('e6000000-0000-4000-8000-000000000001');
select set_config('b.aud', public.save_audience('e6100000-0000-4000-8000-000000000001', null, 'P', 'x')::text, true);
select set_config('b.pauta', public.create_pauta('e6100000-0000-4000-8000-000000000001', 'Pauta')::text, true);
select public.update_pauta(current_setting('b.pauta')::uuid, jsonb_build_object('objective', 'o',
  'audience_ids', jsonb_build_array(current_setting('b.aud')), 'message', 'm', 'cta', 'c'));
select public.mark_pauta_ready(current_setting('b.pauta')::uuid);
select set_config('b.c', public.create_content(current_setting('b.pauta')::uuid, 'instagram', 'post', 'C')::text, true);
select public.save_content_payload(current_setting('b.c')::uuid, '{"body": "Texto"}'::jsonb);
select set_config('b.r', public.submit_for_internal_review(current_setting('b.c')::uuid)::text, true);
select public.complete_internal_review(current_setting('b.r')::uuid, 'approve');
select set_config('b.req', public.request_client_approval(current_setting('b.r')::uuid)::text, true);
select is((select count(*)::integer from public.portal_approvals('e6100000-0000-4000-8000-000000000001')), 1,
  'internal staff can preview the portal read model');
reset role;

select pg_temp.login_as('e6000000-0000-4000-8000-000000000002');
select public.decide_approval(current_setting('b.req')::uuid, 'approve', 'Ok');
select is((select status::text from public.portal_approvals('e6100000-0000-4000-8000-000000000001')), 'approved',
  'the client sees the decided status');
reset role;

select throws_ok($$ update public.approval_decisions set comment = 'adulterado' $$,
  null, null, 'approval decisions are immutable, even for the owner');
select throws_ok($$ delete from public.approval_decisions $$,
  null, null, 'approval decisions cannot be deleted');
select set_eq(
  $$ select action from public.audit_logs where target_id = current_setting('b.req')::uuid $$,
  array['approval.requested', 'approval.approved'],
  'audit action names for client approval');
select is((select count(*)::integer from pg_indexes where indexname = 'approval_requests_one_open'), 1,
  'a partial unique index enforces one open request per content');
select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('approval_decisions_immutable', 'cancel_stale_approval_requests',
                       'client_side_capabilities')
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE')) $$,
  'collaboration helpers are not callable by API roles');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and p.proconfig @> array['search_path=""']
              and p.proname in ('request_client_approval', 'decide_approval',
                                'cancel_approval_request', 'portal_approvals', 'add_comment')), 5,
  'collaboration functions are SECURITY DEFINER with an empty search_path');

select * from finish();
rollback;
