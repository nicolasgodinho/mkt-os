-- Increment 9 / Accepting an invitation
-- PROTECTED ACCEPTANCE TEST (authority: TEST_SPEC). Builders must not edit this file.
-- Contract and fixture: tests/acceptance/increment-9/README.md
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

-- Fixture accounts are confirmed in this same transaction, so they count as accounts confirmed during
-- their invitation's life: by default the session proved the inbox with an e-mail link (amr otp, now).
create function pg_temp.login_as(
  p_user uuid,
  p_session uuid default null,
  p_amr jsonb default jsonb_build_array(jsonb_build_object(
    'method', 'otp', 'timestamp', floor(extract(epoch from now()))::bigint))
) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     jsonb_strip_nulls(jsonb_build_object('sub', p_user, 'role', 'authenticated', 'session_id', p_session, 'amr', p_amr))::text, true);
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
-- Accepting an invitation (docs/05 §1: memberships decide access)
-- ===========================================================================
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.inv_int', t.invitation_id::text, true), set_config('acc.tok_int', t.token, true)
  from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'nova@agencia.test', 'creative') t;
select set_config('acc.tok_cli', t.token, true)
  from public.invite_client_member('a1000000-0000-4000-8000-0000000000a1', 'aprovador@cliente.test', 'approver') t;
select set_config('acc.tok_unc', t.token, true)
  from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'naoconfirmado@agencia.test', 'creative') t;
select set_config('acc.inv_exp', t.invitation_id::text, true), set_config('acc.tok_exp', t.token, true)
  from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'outra@agencia.test', 'analyst') t;
reset role;
select pg_temp.login_as('b0000000-0000-4000-8000-000000000001');
select set_config('acc.tok_b', t.token, true)
  from public.invite_client_member('b1000000-0000-4000-8000-0000000000b1', 'nova@agencia.test', 'viewer') t;
reset role;

-- The token alone is not enough ---------------------------------------------------------
select pg_temp.login_as('d0000000-0000-4000-8000-000000000004');
select throws_ok($$ select * from public.accept_invitation(current_setting('acc.tok_int')) $$,
  '22023', 'this invitation is not valid', 'an invitation is accepted only by the invited e-mail');
reset role;
select pg_temp.login_as('d0000000-0000-4000-8000-000000000003');
select throws_ok($$ select * from public.accept_invitation(current_setting('acc.tok_unc')) $$,
  '22023', 'this invitation is not valid', 'the invited e-mail must be confirmed');
reset role;
select pg_temp.login_as('d0000000-0000-4000-8000-000000000001');
select throws_ok($$ select * from public.accept_invitation('0000000000000000000000000000000000000000000000000000000000000000') $$,
  '22023', 'this invitation is not valid', 'an unknown token is not valid');

-- Internal invitation ---------------------------------------------------------------------
select results_eq($$ select workspace_id, client_id from public.accept_invitation(current_setting('acc.tok_int')) $$,
  $$ values ('a0000000-0000-4000-8000-00000000aaaa'::uuid, null::uuid) $$,
  'accepting returns where the new access is');
select ok('client.view' = any (public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa')),
  'the new internal member has the role''s capabilities right away');
select throws_ok($$ select * from public.accept_invitation(current_setting('acc.tok_int')) $$,
  '22023', 'this invitation is not valid', 'an invitation is used once');

-- A client invitation in another workspace is independent.
select results_eq($$ select workspace_id, client_id from public.accept_invitation(current_setting('acc.tok_b')) $$,
  $$ values ('b0000000-0000-4000-8000-00000000bbbb'::uuid, 'b1000000-0000-4000-8000-0000000000b1'::uuid) $$,
  'one person can be internal in one workspace and a client member in another');
reset role;
select results_eq(
  $$ select role::text, status::text from public.workspace_memberships
      where workspace_id = 'a0000000-0000-4000-8000-00000000aaaa' and user_id = 'd0000000-0000-4000-8000-000000000001' $$,
  $$ values ('creative', 'active') $$,
  'the internal membership is active with the invited role');
select results_eq(
  $$ select status::text, accepted_by from public.invitations where id = current_setting('acc.inv_int')::uuid $$,
  $$ values ('accepted', 'd0000000-0000-4000-8000-000000000001'::uuid) $$,
  'the invitation records who accepted it');

-- Client invitation -----------------------------------------------------------------------
select pg_temp.login_as('d0000000-0000-4000-8000-000000000002');
select results_eq($$ select workspace_id, client_id from public.accept_invitation(current_setting('acc.tok_cli')) $$,
  $$ values ('a0000000-0000-4000-8000-00000000aaaa'::uuid, 'a1000000-0000-4000-8000-0000000000a1'::uuid) $$,
  'a client member joins exactly the invited client');
select ok('approval.decide' = any (public.client_capabilities('a1000000-0000-4000-8000-0000000000a1')),
  'the approver can decide approvals of that client');
select is_empty($$ select 1 from public.clients where id <> 'a1000000-0000-4000-8000-0000000000a1' $$,
  'the new client member sees no other client');
select is(public.workspace_capabilities('a0000000-0000-4000-8000-00000000aaaa'), '{}'::public.capability[],
  'a client member gets no internal access');
reset role;

-- Expired invitations ----------------------------------------------------------------------
update public.invitations set expires_at = now() - interval '1 minute' where id = current_setting('acc.inv_exp')::uuid;
select pg_temp.login_as('d0000000-0000-4000-8000-000000000004');
select throws_ok($$ select * from public.accept_invitation(current_setting('acc.tok_exp')) $$,
  '22023', 'this invitation is not valid', 'an expired invitation cannot be accepted');
reset role;
select is_empty($$ select 1 from public.workspace_memberships where user_id = 'd0000000-0000-4000-8000-000000000004' $$,
  'a refused acceptance grants nothing');
select ok(exists (select 1 from public.audit_logs where target_id = current_setting('acc.inv_int')::uuid
                                                   and action = 'invitation.accepted'),
  'acceptances are audited');

-- Security checks for fresh vs pre-existing accounts --------------------------------------
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.tok_fresh_1', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'nova1@acc.test', 'creative') t;
select set_config('acc.tok_fresh_2', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'nova2@acc.test', 'creative') t;
select set_config('acc.tok_fresh_3', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'nova3@acc.test', 'creative') t;
select set_config('acc.tok_pre', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'preexisting@acc.test', 'creative') t;
select set_config('acc.tok_active', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'active@acc.test', 'creative') t;
select set_config('acc.tok_lost_mgr', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'lost@acc.test', 'creative') t;

reset role;
select pg_temp.make_user('d0000000-0000-4000-8000-000000000005', 'preexisting@acc.test', true);
update auth.users set email_confirmed_at = now() - interval '1 day', encrypted_password = 'hash123', created_at = now() - interval '1 day' where id = 'd0000000-0000-4000-8000-000000000005';
insert into auth.sessions (id, user_id) values ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000005');

select pg_temp.make_user('d0000000-0000-4000-8000-000000000006', 'nova1@acc.test', true);
select pg_temp.make_user('d0000000-0000-4000-8000-000000000007', 'nova2@acc.test', true);
select pg_temp.make_user('d0000000-0000-4000-8000-000000000008', 'nova3@acc.test', true);
update auth.users set encrypted_password = 'hacked' where email in ('nova1@acc.test', 'nova2@acc.test', 'nova3@acc.test');
insert into auth.sessions (id, user_id) values
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000006'),
  ('e0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000007'),
  ('e0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000008'),
  ('e0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000008');

select pg_temp.login_as('d0000000-0000-4000-8000-000000000006', 'e0000000-0000-4000-8000-000000000002', '[{"method": "password", "timestamp": 1}]'::jsonb);
select throws_ok($$ select public.accept_invitation(current_setting('acc.tok_fresh_1')) $$, '42501', 'permission denied', 'fresh account without otp amr is rejected');

select set_config('acc.old_otp', (extract(epoch from now()) - 2000)::text, true);
select pg_temp.login_as('d0000000-0000-4000-8000-000000000007', 'e0000000-0000-4000-8000-000000000003', ('[{"method": "otp", "timestamp": ' || current_setting('acc.old_otp') || '}]')::jsonb);
select throws_ok($$ select public.accept_invitation(current_setting('acc.tok_fresh_2')) $$, '42501', 'permission denied', 'fresh account with old otp is rejected');

select set_config('acc.new_otp', (extract(epoch from now()) - 100)::text, true);
select pg_temp.login_as('d0000000-0000-4000-8000-000000000008', 'e0000000-0000-4000-8000-000000000005', ('[{"method": "otp", "timestamp": ' || current_setting('acc.new_otp') || '}]')::jsonb);
select lives_ok($$ select public.accept_invitation(current_setting('acc.tok_fresh_3')) $$, 'fresh account with recent otp is accepted');
reset role;
select is((select encrypted_password from auth.users where id = 'd0000000-0000-4000-8000-000000000008'), '', 'password is wiped for fresh account');
select set_eq($$ select id from auth.sessions where user_id = 'd0000000-0000-4000-8000-000000000008' $$, $$ values ('e0000000-0000-4000-8000-000000000005'::uuid) $$, 'other sessions are deleted');

reset role;
insert into auth.sessions (id, user_id) values ('e0000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000005');
select pg_temp.login_as('d0000000-0000-4000-8000-000000000005', 'e0000000-0000-4000-8000-000000000009', '[{"method": "password", "timestamp": 1}]'::jsonb);
select lives_ok($$ select public.accept_invitation(current_setting('acc.tok_pre')) $$, 'pre-existing account can use password');
reset role;
select is((select encrypted_password from auth.users where id = 'd0000000-0000-4000-8000-000000000005'), 'hash123', 'password is kept for pre-existing account');
select ok((select count(*) from auth.sessions where user_id = 'd0000000-0000-4000-8000-000000000005') = 2, 'other sessions are kept for pre-existing account');

reset role;
select pg_temp.make_user('d0000000-0000-4000-8000-000000000011', 'active@acc.test', true);
insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status)
  values ('a0000000-0000-4000-8000-00000000aaaa', 'd0000000-0000-4000-8000-000000000011', 'creative', '{}', 'active');
select pg_temp.login_as('d0000000-0000-4000-8000-000000000011', 'e0000000-0000-4000-8000-000000000011', ('[{"method": "otp", "timestamp": ' || current_setting('acc.new_otp') || '}]')::jsonb);
select throws_ok($$ select public.accept_invitation(current_setting('acc.tok_active')) $$, '22023', 'this person is already a member', 'active member cannot accept another invitation to same target');

reset role;
update public.workspace_memberships set role = 'creative', capabilities = '{}' where user_id = 'a0000000-0000-4000-8000-000000000001';
select pg_temp.make_user('d0000000-0000-4000-8000-000000000012', 'lost@acc.test', true);
select pg_temp.login_as('d0000000-0000-4000-8000-000000000012', 'e0000000-0000-4000-8000-000000000012', ('[{"method": "otp", "timestamp": ' || current_setting('acc.new_otp') || '}]')::jsonb);
select throws_ok($$ select public.accept_invitation(current_setting('acc.tok_lost_mgr')) $$, '22023', 'this invitation is not valid', 'fails if inviter lost capabilities');

reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.tok_arch', t.token, true) from public.invite_client_member('a2000000-0000-4000-8000-0000000000a2', 'archived@acc.test', 'viewer') t;
reset role;
update public.clients set status = 'archived' where id = 'a2000000-0000-4000-8000-0000000000a2';
select pg_temp.make_user('d0000000-0000-4000-8000-000000000013', 'archived@acc.test', true);
select pg_temp.login_as('d0000000-0000-4000-8000-000000000013', 'e0000000-0000-4000-8000-000000000013', ('[{"method": "otp", "timestamp": ' || current_setting('acc.new_otp') || '}]')::jsonb);
select throws_ok($$ select public.accept_invitation(current_setting('acc.tok_arch')) $$, '22023', 'this client is archived', 'cannot accept invitation to archived client');

reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.tok_magic', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'magic@acc.test', 'creative') t;
reset role;
select pg_temp.make_user('d0000000-0000-4000-8000-000000000014', 'magic@acc.test', true);
insert into auth.sessions (id, user_id) values ('e0000000-0000-4000-8000-000000000014', 'd0000000-0000-4000-8000-000000000014');
select pg_temp.login_as('d0000000-0000-4000-8000-000000000014', 'e0000000-0000-4000-8000-000000000014', ('[{"method": "magiclink", "timestamp": ' || current_setting('acc.new_otp') || '}]')::jsonb);
select lives_ok($$ select public.accept_invitation(current_setting('acc.tok_magic')) $$, 'fresh account with recent magiclink is accepted');

reset role;
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.inv_a_id', t.invitation_id::text, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'mult@acc.test', 'creative') t;
reset role;
select pg_temp.make_user('d0000000-0000-4000-8000-000000000015', 'mult@acc.test', true);
update auth.users set encrypted_password = 'hacked' where id = 'd0000000-0000-4000-8000-000000000015';
insert into auth.sessions (id, user_id) values ('e0000000-0000-4000-8000-000000000015', 'd0000000-0000-4000-8000-000000000015');
select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select public.revoke_invitation(current_setting('acc.inv_a_id')::uuid);
select set_config('acc.tok_b', t.token, true) from public.invite_workspace_member('a0000000-0000-4000-8000-00000000aaaa', 'mult@acc.test', 'creative') t;
reset role;

select pg_temp.login_as('d0000000-0000-4000-8000-000000000015', 'e0000000-0000-4000-8000-000000000015', '[{"method": "password", "timestamp": 1}]'::jsonb);
select throws_ok($$ select public.accept_invitation(current_setting('acc.tok_b')) $$, '42501', 'permission denied', 'freshness considers earliest invitation');

select pg_temp.login_as('d0000000-0000-4000-8000-000000000015', 'e0000000-0000-4000-8000-000000000015', ('[{"method": "otp", "timestamp": ' || current_setting('acc.new_otp') || '}]')::jsonb);
select lives_ok($$ select public.accept_invitation(current_setting('acc.tok_b')) $$, 'fresh account with recent otp accepted on second invitation');
reset role;
select is((select encrypted_password from auth.users where id = 'd0000000-0000-4000-8000-000000000015'), '', 'password wiped after proven acceptance');

select pg_temp.login_as('a0000000-0000-4000-8000-000000000001');
select set_config('acc.tok_c', t.token, true) from public.invite_client_member('a1000000-0000-4000-8000-0000000000a1', 'mult@acc.test', 'viewer') t;
reset role;

update auth.users set encrypted_password = 'newpassword' where id = 'd0000000-0000-4000-8000-000000000015';
select pg_temp.login_as('d0000000-0000-4000-8000-000000000015', 'e0000000-0000-4000-8000-000000000015', '[{"method": "password", "timestamp": 1}]'::jsonb);
select lives_ok($$ select public.accept_invitation(current_setting('acc.tok_c')) $$, 'proven account can accept later invitation with password');
reset role;
select is((select encrypted_password from auth.users where id = 'd0000000-0000-4000-8000-000000000015'), 'newpassword', 'password kept on proven account');

select * from finish();
rollback;
