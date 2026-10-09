-- Builder tests for Increment 9 (ExecPlan 0009): hardening the protected TEST_SPEC does not
-- freeze — definer functions, helper privileges, table constraints.
begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosecdef and p.proconfig @> array['search_path=""']
              and p.proname in ('invite_workspace_member', 'invite_client_member',
                                'revoke_invitation', 'accept_invitation', 'workspace_members',
                                'client_members', 'hook_before_user_created')), 7,
  'invitation functions are SECURITY DEFINER with an empty search_path');
select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app'
     and p.proname in ('normalize_email', 'require_email', 'user_by_email', 'create_invitation')
     and (has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE')) $$,
  'invitation helpers are not callable by API roles');

insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
  ('e9000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'inv-admin@builder.test', now(), now());
insert into public.users (id, display_name) values
  ('e9000000-0000-4000-8000-000000000001', 'inv-admin') on conflict (id) do nothing;
insert into public.workspaces (id, name, slug) values
  ('e9000000-0000-4000-8000-00000000aaaa', 'Builder Invitations', 'builder-invitations');

select throws_ok(
  $$ insert into public.invitations (workspace_id, email, workspace_role, client_role, token_hash, invited_by)
     values ('e9000000-0000-4000-8000-00000000aaaa', 'x@y.test', 'creative', 'viewer',
             repeat('a', 64), 'e9000000-0000-4000-8000-000000000001') $$,
  '23514', null, 'an invitation is either internal (workspace role) or for a client (client role)');
select throws_ok(
  $$ insert into public.invitations (workspace_id, email, workspace_role, token_hash, invited_by)
     values ('e9000000-0000-4000-8000-00000000aaaa', 'Upper@Case.test', 'creative', repeat('b', 64),
             'e9000000-0000-4000-8000-000000000001') $$,
  '23514', null, 'stored e-mails are normalized to lowercase');
select throws_ok(
  $$ insert into public.invitations (workspace_id, email, workspace_role, token_hash, invited_by)
     values ('e9000000-0000-4000-8000-00000000aaaa', 'a@b.test', 'creative', 'plain-token',
             'e9000000-0000-4000-8000-000000000001') $$,
  '23514', null, 'only a SHA-256 hex digest fits the token column');

select * from finish();
rollback;
