-- Builder tests for Increment 2 (ExecPlan 0002). They cover builder decisions that the protected
-- TEST_SPEC deliberately does not freeze: table-level integrity (defense in depth below the API),
-- input normalization, conflict recomputation edge cases, audit action names and idempotence.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

create function pg_temp.login_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Fixture: one workspace, two clients, one admin.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e0000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'brain-admin@builder.test', now(), now());
insert into public.users (id, display_name)
values ('e0000000-0000-4000-8000-000000000001', 'brain-admin') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e0000000-0000-4000-8000-00000000aaaa', 'Builder Brain', 'builder-brain');
insert into public.clients (id, workspace_id, name, slug) values
  ('e1000000-0000-4000-8000-000000000001', 'e0000000-0000-4000-8000-00000000aaaa', 'Brain C1', 'brain-c1'),
  ('e1000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-00000000aaaa', 'Brain C2', 'brain-c2');
insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('e0000000-0000-4000-8000-00000000aaaa', 'e0000000-0000-4000-8000-000000000001', 'admin', 'active');

select pg_temp.login_as('e0000000-0000-4000-8000-000000000001');
select set_config('b.src1', public.create_source('e1000000-0000-4000-8000-000000000001',
  'document', 'Briefing', 'FIRST_PARTY')::text, true);
select set_config('b.src2', public.create_source('e1000000-0000-4000-8000-000000000002',
  'document', 'Briefing C2', 'FIRST_PARTY')::text, true);

-- ---------------------------------------------------------------------------
-- Input normalization and validation
-- ---------------------------------------------------------------------------
select set_config('b.norm', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST', '  CTA  ', 'Use CTA', '  Instagram ')::text, true);
select is((select subject from public.rules where id = current_setting('b.norm')::uuid), 'cta',
  'subjects are trimmed and lowercased');
select is((select channel || '/' || scope_type::text from public.rules
            where id = current_setting('b.norm')::uuid), 'instagram/channel',
  'channels are normalized and imply channel scope');
select throws_ok($$ select public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST', 'x', 'x', 'insta gram') $$,
  '22023', null, 'a channel key with spaces is rejected');
select throws_ok($$ select public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'PREFER', null, 'x', null, 101) $$,
  '22023', null, 'priority above 100 is rejected');
select throws_ok($$ select public.propose_insight('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'x', 1.5) $$,
  '22023', null, 'confidence above 1 is rejected');

-- Archive is idempotent: one transition, one audit entry.
select set_config('b.aud', public.save_audience('e1000000-0000-4000-8000-000000000001', null,
  'Público 2', 'x')::text, true);
select public.archive_context_item('audience', current_setting('b.aud')::uuid);
select lives_ok($$ select public.archive_context_item('audience', current_setting('b.aud')::uuid) $$,
  'archiving an archived item is a no-op');
reset role;
select is((select count(*)::integer from public.audit_logs
            where target_id = current_setting('b.aud')::uuid and action = 'audience.archived'), 1,
  'a repeated archive is audited once');

-- ---------------------------------------------------------------------------
-- Table-level integrity (holds even for a buggy function or a privileged writer)
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.facts (client_id, source_id, statement, proposed_by)
  values ('e1000000-0000-4000-8000-000000000001', current_setting('b.src2')::uuid, 'x',
          'e0000000-0000-4000-8000-000000000001') $$,
  '23503', null, 'a fact can never reference a source of another client');
select throws_ok($$ insert into public.rules (client_id, source_id, type, statement, proposed_by)
  values ('e1000000-0000-4000-8000-000000000001', current_setting('b.src1')::uuid, 'MUST_NOT', 'x',
          'e0000000-0000-4000-8000-000000000001') $$,
  '23514', null, 'a hard rule without subject violates a check constraint');
select throws_ok($$ insert into public.rules (client_id, source_id, type, subject, statement, scope_type, proposed_by)
  values ('e1000000-0000-4000-8000-000000000001', current_setting('b.src1')::uuid, 'PREFER', null, 'x',
          'channel', 'e0000000-0000-4000-8000-000000000001') $$,
  '23514', null, 'channel scope requires a channel');
select throws_ok($$ insert into public.sources (client_id, type, title, trust_level, created_by)
  values ('e1000000-0000-4000-8000-000000000001', 'document', 'x', 'SYSTEM',
          'e0000000-0000-4000-8000-000000000001') $$,
  '23514', null, 'SYSTEM trust is reserved at the table level too');
select throws_ok($$ update public.audit_logs set action = 'forged'
                     where target_id = current_setting('b.aud')::uuid $$,
  null, null, 'Client Brain audit entries stay append-only');

-- ---------------------------------------------------------------------------
-- Conflict recomputation edge cases
-- ---------------------------------------------------------------------------
select pg_temp.login_as('e0000000-0000-4000-8000-000000000001');
select set_config('b.m1', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST', 'tom', 'Tom formal')::text, true);
select set_config('b.m2', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST', 'tom', 'Tom técnico')::text, true);
select is(public.activate_rule(current_setting('b.m1')::uuid)::text, 'active', 'first MUST activates');
select is(public.activate_rule(current_setting('b.m2')::uuid)::text, 'active',
  'two MUST rules on one subject never conflict');

select set_config('b.a1', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST', 'emoji', 'Use emojis')::text, true);
select set_config('b.a2', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST_NOT', 'emoji', 'Sem emojis')::text, true);
select public.activate_rule(current_setting('b.a1')::uuid);
select is(public.activate_rule(current_setting('b.a2')::uuid)::text, 'conflict', 'setup: conflict');
select set_config('b.a3', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'MUST', 'icones', 'Use ícones no lugar de emojis', null, 50,
  null, null, current_setting('b.a1')::uuid)::text, true);
select is(public.activate_rule(current_setting('b.a3')::uuid)::text, 'active',
  'a rule may supersede a rule with another subject');
select is((select status::text from public.rules where id = current_setting('b.a2')::uuid), 'active',
  'superseding one side releases the other side on the old subject');

select set_config('b.p1', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'AVOID', null, 'Evite gírias')::text, true);
select set_config('b.p2', public.propose_rule('e1000000-0000-4000-8000-000000000001',
  current_setting('b.src1')::uuid, 'AVOID', null, 'Evite gírias regionais', null, 50, null, null,
  current_setting('b.p1')::uuid)::text, true);
select throws_ok($$ select public.activate_rule(current_setting('b.p2')::uuid) $$,
  '22023', null, 'a rule can only supersede an active or conflicting rule');
select throws_ok($$ select public.propose_rule('e1000000-0000-4000-8000-000000000002',
  current_setting('b.src2')::uuid, 'AVOID', null, 'x', null, 50, null, null,
  current_setting('b.p1')::uuid) $$,
  'P0002', null, 'supersession never crosses clients, even inside one workspace');
reset role;

select isnt_empty($$ select 1 from public.audit_logs
                    where target_id = current_setting('b.a1')::uuid and action = 'rule.conflict_detected' $$,
  'entering a conflict is audited');
select isnt_empty($$ select 1 from public.audit_logs
                    where target_id = current_setting('b.a2')::uuid and action = 'rule.conflict_resolved' $$,
  'leaving a conflict is audited');
select is_empty($$ select 1 from public.audit_logs
                  where client_id = 'e1000000-0000-4000-8000-000000000001'
                    and (coalesce(before::text, '') || coalesce(after::text, '')) like '%Use emojis%' $$,
  'rule statements are never copied into the audit trail');

-- ---------------------------------------------------------------------------
-- Privileges of the internal helpers
-- ---------------------------------------------------------------------------
select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('require_client_capability', 'require_item_capability', 'require_text',
                       'client_source_trust', 'recompute_rule_conflicts', 'review_knowledge')
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE')) $$,
  'Client Brain helpers are not callable by API roles');
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef
              and p.proname in ('save_brand_profile', 'save_audience', 'save_offer', 'save_region',
                                'archive_context_item', 'create_source', 'propose_fact',
                                'propose_decision', 'propose_insight', 'approve_knowledge',
                                'reject_knowledge', 'propose_rule', 'activate_rule', 'reject_rule',
                                'effective_rules', 'rule_conflicts')
              and p.proconfig @> array['search_path=""']), 16,
  'all 16 Client Brain functions are SECURITY DEFINER with an empty search_path');
select is_empty($$ select 1 from public.rules
                  where client_id = '20000000-0000-4000-8000-00000000000a' and status = 'conflict' $$,
  'the seeded Client Brain has no rule conflict');

select * from finish();
rollback;
