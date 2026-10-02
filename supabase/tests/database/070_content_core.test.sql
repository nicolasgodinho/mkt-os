-- Builder tests for Increment 5 (ExecPlan 0005): decisions the protected TEST_SPEC does not freeze —
-- payload validation details, hash determinism, audit action names, helper privileges.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e5000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'content-admin@builder.test', now(), now());
insert into public.users (id, display_name)
values ('e5000000-0000-4000-8000-000000000001', 'content-admin') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e5000000-0000-4000-8000-00000000aaaa', 'Builder Content', 'builder-content');
insert into public.clients (id, workspace_id, name, slug) values
  ('e5100000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-00000000aaaa', 'Content C1', 'content-c1');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e5000000-0000-4000-8000-00000000aaaa', 'e5000000-0000-4000-8000-000000000001', 'admin', 'active');

select pg_temp.login_as('e5000000-0000-4000-8000-000000000001');
select set_config('b.aud', public.save_audience('e5100000-0000-4000-8000-000000000001', null, 'P', 'x')::text, true);
select set_config('b.pauta', public.create_pauta('e5100000-0000-4000-8000-000000000001', 'Pauta')::text, true);
select public.update_pauta(current_setting('b.pauta')::uuid, jsonb_build_object(
  'objective', 'o', 'audience_ids', jsonb_build_array(current_setting('b.aud')), 'message', 'm', 'cta', 'c'));
select public.mark_pauta_ready(current_setting('b.pauta')::uuid);
select set_config('b.c1', public.create_content(current_setting('b.pauta')::uuid, ' Instagram ', 'Reel', 'A')::text, true);
select set_config('b.c2', public.create_content(current_setting('b.pauta')::uuid, 'linkedin', 'post', 'B')::text, true);

select is((select channel || '/' || format from public.contents where id = current_setting('b.c1')::uuid),
  'instagram/reel', 'channel and format are normalized');
select throws_ok($$ select public.save_content_payload(current_setting('b.c1')::uuid,
                    '{"body": "x", "hashtags": "#um"}'::jsonb) $$,
  '22023', null, 'hashtags must be an array of strings');
select throws_ok($$ select public.save_content_payload(current_setting('b.c1')::uuid,
                    '{"body": 42}'::jsonb) $$,
  '22023', null, 'payload text fields must be strings');
select public.save_content_payload(current_setting('b.c1')::uuid, '{"body": "Mesmo texto"}'::jsonb);
select public.save_content_payload(current_setting('b.c2')::uuid, '{"body": "Mesmo texto"}'::jsonb);
select set_config('b.r1', public.submit_for_internal_review(current_setting('b.c1')::uuid)::text, true);
select set_config('b.r2', public.submit_for_internal_review(current_setting('b.c2')::uuid)::text, true);
select throws_ok($$ select public.submit_for_internal_review(current_setting('b.c1')::uuid) $$,
  '22023', null, 'content already under review cannot be submitted again');
select throws_ok($$ select public.complete_internal_review(current_setting('b.r1')::uuid, 'publish') $$,
  '22023', null, 'unknown review decisions are rejected');
select set_config('b.init', public.create_initiative('e5100000-0000-4000-8000-000000000001', 'launch', 'L')::text, true);
select public.set_initiative_status(current_setting('b.init')::uuid, 'planning');
select public.set_initiative_status(current_setting('b.init')::uuid, 'paused');
select throws_ok($$ select public.set_initiative_status(current_setting('b.init')::uuid, 'active') $$,
  '22023', null, 'a paused initiative cannot skip ahead when resuming');
select lives_ok($$ select public.set_initiative_status(current_setting('b.init')::uuid, 'planning') $$,
  'a paused initiative resumes to the state it was paused in');
select throws_ok($$ select public.update_pauta(current_setting('b.pauta')::uuid, '{"offer_id": "nope"}'::jsonb) $$,
  '22023', null, 'a malformed offer id is an invalid argument');
select set_config('b.opp', public.create_opportunity('e5100000-0000-4000-8000-000000000001', 'trend', 'T', 'R')::text, true);
select throws_ok($$ select public.create_opportunity('e5100000-0000-4000-8000-000000000001', 'Not A Type', 'T', 'R') $$,
  '22023', null, 'opportunity types are lowercase keys');
reset role;

select is((select immutable_hash from public.content_revisions where id = current_setting('b.r1')::uuid),
          (select immutable_hash from public.content_revisions where id = current_setting('b.r2')::uuid),
  'the revision hash depends only on the payload');
select set_eq(
  $$ select distinct action from public.audit_logs
      where client_id = 'e5100000-0000-4000-8000-000000000001' $$,
  array['audience.saved', 'pauta.created', 'pauta.updated', 'pauta.ready', 'content.created',
        'content.edited', 'content.submitted', 'opportunity.created', 'initiative.created',
        'initiative.status_changed'],
  'audit action names for the content core');
select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('optional_text', 'client_refs', 'pauta_missing', 'revision_rules',
                       'validate_content_payload', 'require_reviewable_revision',
                       'content_revisions_immutable')
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE')) $$,
  'content helpers are not callable by API roles');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and p.proconfig @> array['search_path=""']
              and p.proname in ('create_initiative', 'set_initiative_status', 'create_opportunity',
                                'review_opportunity', 'convert_opportunity', 'create_pauta',
                                'update_pauta', 'pauta_readiness', 'mark_pauta_ready',
                                'create_content', 'save_content_payload',
                                'submit_for_internal_review', 'record_rule_check',
                                'revision_validation', 'complete_internal_review')), 15,
  'all 15 content functions are SECURITY DEFINER with an empty search_path');
select throws_ok($$ truncate public.content_revisions cascade $$,
  null, null, 'revisions cannot be truncated');

select * from finish();
rollback;
