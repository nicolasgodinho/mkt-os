-- Builder tests for Increment 7 (ExecPlan 0007): decisions the protected TEST_SPEC does not
-- freeze — audit action names, function hardening, table constraints, deadline on closed content.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create function pg_temp.claims(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e7000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cal-admin@builder.test', now(), now()),
  ('e7000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cal-client@builder.test', now(), now());
insert into public.users (id, display_name) values
  ('e7000000-0000-4000-8000-000000000001', 'cal-admin'),
  ('e7000000-0000-4000-8000-000000000002', 'cal-client') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e7000000-0000-4000-8000-00000000aaaa', 'Builder Calendar', 'builder-calendar');
insert into public.clients (id, workspace_id, name, slug) values
  ('e7100000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-00000000aaaa', 'Cal C1', 'cal-c1');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e7000000-0000-4000-8000-00000000aaaa', 'e7000000-0000-4000-8000-000000000001', 'admin', 'active');
insert into public.client_memberships (client_id, user_id, role, status) values
  ('e7100000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000002', 'approver', 'active');

select pg_temp.claims('e7000000-0000-4000-8000-000000000001');
select set_config('b.aud', public.save_audience('e7100000-0000-4000-8000-000000000001', null, 'P', 'x')::text, true);
select set_config('b.pauta', public.create_pauta('e7100000-0000-4000-8000-000000000001', 'Pauta')::text, true);
select public.update_pauta(current_setting('b.pauta')::uuid, jsonb_build_object('objective', 'o',
  'audience_ids', jsonb_build_array(current_setting('b.aud')), 'message', 'm', 'cta', 'c'));
select public.mark_pauta_ready(current_setting('b.pauta')::uuid);
select set_config('b.c', public.create_content(current_setting('b.pauta')::uuid, 'instagram', 'post', 'C')::text, true);
select public.save_content_payload(current_setting('b.c')::uuid, '{"body": "Texto"}'::jsonb);
select set_config('b.r', public.submit_for_internal_review(current_setting('b.c')::uuid)::text, true);
select public.complete_internal_review(current_setting('b.r')::uuid, 'approve');
select set_config('b.req', public.request_client_approval(current_setting('b.r')::uuid)::text, true);
select pg_temp.claims('e7000000-0000-4000-8000-000000000002');
select public.decide_approval(current_setting('b.req')::uuid, 'approve');
select pg_temp.claims('e7000000-0000-4000-8000-000000000001');
select set_config('b.p', public.schedule_publication(current_setting('b.c')::uuid, now() + interval '2 days')::text, true);
select public.reschedule_publication(current_setting('b.p')::uuid, now() + interval '3 days');
select public.set_production_deadline(current_setting('b.c')::uuid, now() + interval '1 day');
select public.mark_publication_published(current_setting('b.p')::uuid, 'https://example.com/p/1');

select set_eq(
  $$ select action from public.audit_logs
      where target_id in (current_setting('b.p')::uuid, current_setting('b.c')::uuid)
        and (action like 'publication.%' or action = 'content.deadline_set') $$,
  array['publication.scheduled', 'publication.rescheduled', 'publication.published',
        'content.deadline_set'],
  'audit action names for the publication schedule');

update public.contents set status = 'canceled' where id = current_setting('b.c')::uuid;
select throws_ok($$ select public.set_production_deadline(current_setting('b.c')::uuid, now()) $$,
  '22023', 'this content can no longer be edited', 'canceled content takes no deadline');

select throws_ok($$ update public.publications set remote_url = 'ftp://x' where id = current_setting('b.p')::uuid $$,
  '23514', null, 'the table refuses non-http(s) links even for the owner');
select throws_ok($$ update public.publications set published_at = null where id = current_setting('b.p')::uuid $$,
  '23514', null, 'a published publication always has its publication time');
select throws_ok(
  $$ update public.publications set revision_id = gen_random_uuid() where id = current_setting('b.p')::uuid $$,
  '23503', null, 'a publication references a revision of its own content');

select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and p.proconfig @> array['search_path=""']
              and p.proname in ('schedule_publication', 'reschedule_publication', 'cancel_publication',
                                'mark_publication_published', 'set_production_deadline',
                                'calendar_events')), 6,
  'calendar functions are SECURITY DEFINER with an empty search_path');
select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('schedule_publication', 'reschedule_publication', 'cancel_publication',
                       'mark_publication_published', 'set_production_deadline', 'calendar_events')
     and has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  'anon cannot call the calendar API');

select * from finish();
rollback;
