-- Increment 9 / Creating and revoking invitations; invite-only signup hook
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-9/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

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

-- An Auth identity as Supabase stores it; `p_confirmed` sets email_confirmed_at.
create function pg_temp.make_user(p_id uuid, p_email text, p_confirmed boolean default true)
returns void language plpgsql as $$
begin
  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_email, case when p_confirmed then now() end, now(), now());
  insert into public.users (id, display_name) values (p_id, p_email) on conflict (id) do nothing;
end;
$$;

-- What Supabase Auth sends to the before_user_created hook.
create function pg_temp.signup_event(p_email text) returns jsonb language sql as $$
  select jsonb_build_object('metadata', jsonb_build_object('name', 'before-user-created'),
                            'user', jsonb_build_object('email', p_email, 'aud', 'authenticated'));
$$;

-- ---------------------------------------------------------------------------
-- Fixture (see README): Workspace A {A1, A2}, Workspace B {B1}
-- ---------------------------------------------------------------------------
select pg_temp.make_user(id, email, confirmed) from (values
  ('a0000000-0000-4000-8000-000000000001'::uuid, 'a_admin@acc.test', true),
  ('a0000000-0000-4000-8000-000000000004'::uuid, 'a_strategist@acc.test', true),
  ('a0000000-0000-4000-8000-000000000009'::uuid, 'a_mgr@acc.test', true),
  ('b0000000-0000-4000-8000-000000000001'::uuid, 'b_admin@acc.test', true),
  ('c1000000-0000-4000-8000-000000000001'::uuid, 'a1_cadmin@acc.test', true),
  -- People who arrive through invitations.
  ('d0000000-0000-4000-8000-000000000001'::uuid, 'nova@agencia.test', true),
  ('d0000000-0000-4000-8000-000000000002'::uuid, 'aprovador@cliente.test', true),
  ('d0000000-0000-4000-8000-000000000003'::uuid, 'naoconfirmado@agencia.test', false),
  ('d0000000-0000-4000-8000-000000000004'::uuid, 'outra@agencia.test', true)
) as u(id, email, confirmed);

insert into public.workspaces (id, name, slug) values
  ('a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Workspace A', 'acc-ws-a'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'Secret Workspace B', 'acc-ws-b');

insert into public.clients (id, workspace_id, name, slug) values
  ('a1000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Client A1', 'acc-client-a1'),
  ('a2000000-0000-4000-8000-0000000000a2', 'a0000000-0000-4000-8000-00000000aaaa', 'Acceptance Client A2', 'acc-client-a2'),
  ('b1000000-0000-4000-8000-0000000000b1', 'b0000000-0000-4000-8000-00000000bbbb', 'Secret Client B1', 'acc-client-b1');

insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status) values
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000004', 'strategist', '{}', 'active'),
  ('a0000000-0000-4000-8000-00000000aaaa', 'a0000000-0000-4000-8000-000000000009', 'strategist', '{client.manage}', 'active'),
  ('b0000000-0000-4000-8000-00000000bbbb', 'b0000000-0000-4000-8000-000000000001', 'admin', '{}', 'active');

insert into public.client_memberships (client_id, user_id, role, capabilities, status) values
  ('a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001', 'client_admin', '{}', 'active');

-- ===========================================================================
-- Creating and revoking invitations (docs/03 "memberships/invite")
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.inv1', t.invitation_id::text, true), set_config('acc.tok1', t.token, true)
  from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', '  Nova@Agencia.TEST ',
                                      'creative', '{content.review_internal}') t;
reset role;
select results_eq(
  $$ select workspace_id, client_id, email, workspace_role::text, capabilities::text[], status::text,
            expires_at, invited_by
       from public.invitations where id = current_setting('acc.inv1')::uuid $$,
  $$ values ('a0000000-0000-4000-8000-00000000aaaa'::uuid, null::uuid, 'nova@agencia.test', 'creative',
             array['content.review_internal'], 'pending', now() + interval '7 days',
             'a0000000-0000-4000-8000-000000000001'::uuid) $$,
  'an invitation stores the normalized e-mail, the role and capabilities, and expires in 7 days');
select ok(current_setting('acc.tok1') ~ '^[0-9a-f]{64}$', 'the token is 256 random bits, shown once');
select is_empty($$ select 1 from public.invitations
                    where token_hash = current_setting('acc.tok1') or token_hash like '%' || current_setting('acc.tok1') || '%' $$,
  'only a hash of the token is stored');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select * from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'sem-arroba', 'creative') $$,
  '22023', 'invalid email', 'an e-mail address is required');
select throws_ok($$ select * from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'A_Strategist@acc.test', 'creative') $$,
  '22023', 'this person is already a member', 'active members are not invited again');
select throws_ok($$ select * from public.invite_client_member('a1000000-0000-4000-8000-0000000000a1', 'x@cliente.test', 'viewer', '{client.manage}') $$,
  '22023', 'client memberships can only hold client-safe capabilities', 'client invitations stay client-safe');
select throws_ok($$ select * from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'a1_cadmin@acc.test', 'creative') $$,
  '22023', 'a client-side member cannot become an internal member of the same workspace',
  'internal and client-side identities stay separate within a workspace');

-- Inviting the same person again replaces the pending invitation.
select set_config('acc.inv2', (select invitation_id::text from public.invite_workspace_member(
  'a0000000-0000-4000-8000-00000000aaaa', 'nova@agencia.test', 'strategist')), true);
reset role;
select results_eq(
  $$ select (select status::text from public.invitations where id = current_setting('acc.inv1')::uuid),
            (select count(*)::integer from public.invitations where email = 'nova@agencia.test' and status = 'pending') $$,
  $$ values ('revoked', 1) $$,
  'a new invitation for the same person and target revokes the previous one');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.revoke_invitation(current_setting('acc.inv2')::uuid);
select throws_ok($$ select public.revoke_invitation(current_setting('acc.inv2')::uuid) $$,
  '22023', 'this invitation is no longer pending', 'an invitation is revoked once');
reset role;
select is((select status::text from public.invitations where id = current_setting('acc.inv2')::uuid),
  'revoked', 'revoking an invitation closes it');

-- ===========================================================================
-- Signup is invite-only: the before_user_created Auth hook
-- ===========================================================================
select is((public.hook_before_user_created(pg_temp.signup_event('desconhecido@x.test')) -> 'error' ->> 'http_code')::integer,
  403, 'a signup without an invitation is rejected');
select is((public.hook_before_user_created(pg_temp.signup_event('nova@agencia.test')) -> 'error' ->> 'http_code')::integer,
  403, 'a revoked invitation does not allow a signup');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.inv3', (select invitation_id::text from public.invite_client_member(
  'a1000000-0000-4000-8000-0000000000a1', 'convidada@cliente.test', 'viewer')), true);
reset role;
select is(public.hook_before_user_created(pg_temp.signup_event('  Convidada@Cliente.test ')), '{}'::jsonb,
  'a pending invitation allows the signup (e-mail compared normalized)');
update public.invitations set expires_at = now() - interval '1 minute' where id = current_setting('acc.inv3')::uuid;
select is((public.hook_before_user_created(pg_temp.signup_event('convidada@cliente.test')) -> 'error' ->> 'http_code')::integer,
  403, 'an expired invitation does not allow a signup');

-- Members list and audit ---------------------------------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_eq(
  $$ select email, role::text, status::text from public.workspace_members('a0000000-0000-4000-8000-00000000aaaa') $$,
  $$ values ('a_admin@acc.test', 'admin', 'active'), ('a_strategist@acc.test', 'strategist', 'active'),
            ('a_mgr@acc.test', 'strategist', 'active') $$,
  'workspace managers list their members with e-mail, role and status');
select set_eq(
  $$ select email, role::text from public.client_members('a1000000-0000-4000-8000-0000000000a1') $$,
  $$ values ('a1_cadmin@acc.test', 'client_admin') $$,
  'client managers list the client''s members');
reset role;
select set_eq(
  $$ select distinct action from public.audit_logs where target_id in
       (current_setting('acc.inv1')::uuid, current_setting('acc.inv2')::uuid) $$,
  array['invitation.created', 'invitation.revoked'],
  'invitations are audited');

-- Additional constraints ---------------------------------------------------------------
reset role;
update public.clients set status = 'archived' where id = 'a2000000-0000-4000-8000-0000000000a2';
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select * from public.invite_client_member('a2000000-0000-4000-8000-0000000000a2', 'xyz@cliente.test', 'viewer') $$,
  '22023', 'this client is archived', 'cannot invite to an archived client');

-- A pending invitation of someone who then becomes a member is revoked with the membership.
select set_config('acc.inv_rev', (select invitation_id::text from public.invite_workspace_member(
  'a0000000-0000-4000-8000-00000000aaaa', 'outra@agencia.test', 'creative')), true);
reset role;
insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status)
  values ('a0000000-0000-4000-8000-00000000aaaa', 'd0000000-0000-4000-8000-000000000004', 'creative', '{}', 'active');
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.revoke_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'd0000000-0000-4000-8000-000000000004');
reset role;
select is((select status::text from public.invitations where id = current_setting('acc.inv_rev')::uuid),
  'revoked', 'revoking a member revokes their pending invitations');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select throws_ok($$ select public.revoke_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'd0000000-0000-4000-8000-000000000001') $$,
  '22023', 'no membership to revoke', 'revoking a non-member still raises the original error');
reset role;

-- The operator bootstrap creates the first invitation without an inviter.
select lives_ok($$ insert into public.invitations (workspace_id, email, token_hash, workspace_role, expires_at, invited_by)
  values ('a0000000-0000-4000-8000-00000000aaaa', 'null_inviter@acc.test',
          encode(sha256(convert_to('null-inviter', 'UTF8')), 'hex'), 'creative', now() + interval '7 days', null) $$,
  'invited_by accepts NULL');

select * from finish();
rollback;
