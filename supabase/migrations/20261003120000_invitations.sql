-- Increment 9 — Administration and invitations (ExecPlan 0009, ADR 0005).
--
-- * People join through invitations: workspace managers invite internal members, client managers
--   invite portal members. Only a SHA-256 hash of the one-time token is stored.
-- * Signup stays invite-only, enforced by the database: Supabase Auth calls
--   `public.hook_before_user_created`, which rejects any e-mail without a pending invitation.
--   No service-role key is involved anywhere in the app.
-- * Acceptance runs for the signed-in user and requires the invited, confirmed e-mail.
-- Contract: tests/acceptance/increment-9/README.md.

create type public.invitation_status as enum ('pending', 'accepted', 'revoked', 'expired');

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id),
  -- Null for an internal (workspace) invitation; the client for a portal invitation.
  client_id uuid,
  email text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and email = lower(email)
                             and char_length(email) <= 320),
  workspace_role public.workspace_role,
  client_role public.client_role,
  capabilities public.capability[] not null default '{}',
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null default now() + interval '7 days',
  invited_by uuid not null references public.users (id),
  accepted_by uuid references public.users (id),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (client_id, workspace_id) references public.clients (id, workspace_id),
  check ((client_id is null) = (workspace_role is not null)
         and (client_id is null) = (client_role is null))
);
-- One pending invitation per person and target.
create unique index invitations_one_pending on public.invitations
  (workspace_id, coalesce(client_id, '00000000-0000-0000-0000-000000000000'::uuid), email)
  where status = 'pending';
create index invitations_email_pending_idx on public.invitations (email) where status = 'pending';

create function app.normalize_email(p_email text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(lower(btrim(p_email)), '');
$$;

create function app.require_email(p_email text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_email text := app.normalize_email(p_email);
begin
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or char_length(v_email) > 320 then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  return v_email;
end;
$$;

-- The Auth user (if any) that owns an e-mail.
create function app.user_by_email(p_email text)
returns uuid
language sql
stable
set search_path = ''
as $$
  select u.id from auth.users u where lower(u.email) = p_email limit 1;
$$;

-- Creates an invitation (replacing the pending one for the same person and target) and returns
-- its id with the one-time token.
create function app.create_invitation(
  p_workspace_id uuid,
  p_client_id uuid,
  p_email text,
  p_workspace_role public.workspace_role,
  p_client_role public.client_role,
  p_capabilities public.capability[],
  p_inviter uuid,
  out invitation_id uuid,
  out token text
)
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_revoked uuid;
begin
  for v_revoked in
    update public.invitations i set status = 'revoked'
     where i.workspace_id = p_workspace_id and i.client_id is not distinct from p_client_id
       and i.email = p_email and i.status = 'pending'
    returning i.id
  loop
    perform app.audit(p_workspace_id, p_client_id, 'invitation.revoked', 'invitation', v_revoked,
                      jsonb_build_object('status', 'pending'),
                      jsonb_build_object('status', 'revoked', 'reason', 'replaced'));
  end loop;

  token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.invitations (workspace_id, client_id, email, workspace_role, client_role,
                                  capabilities, token_hash, invited_by)
  values (p_workspace_id, p_client_id, p_email, p_workspace_role, p_client_role, p_capabilities,
          encode(sha256(convert_to(token, 'UTF8')), 'hex'), p_inviter)
  returning id into invitation_id;
  perform app.audit(p_workspace_id, p_client_id, 'invitation.created', 'invitation', invitation_id,
                    null,
                    jsonb_build_object('email', p_email, 'workspace_role', p_workspace_role,
                                       'client_role', p_client_role,
                                       'capabilities', p_capabilities));
end;
$$;

-- -----------------------------------------------------------------------------
-- Invitation API
-- -----------------------------------------------------------------------------
create function public.invite_workspace_member(
  p_workspace_id uuid,
  p_email text,
  p_role public.workspace_role,
  p_capabilities public.capability[] default '{}'
)
returns table (invitation_id uuid, token text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_email text;
  v_user uuid;
  v_result record;
begin
  perform app.require_workspace_manager(v_uid, p_workspace_id);
  v_email := app.require_email(p_email);
  if p_role is null then
    raise exception 'role is required' using errcode = '22023';
  end if;
  v_user := app.user_by_email(v_email);
  if v_user is not null then
    if exists (select 1 from public.workspace_memberships m
                where m.workspace_id = p_workspace_id and m.user_id = v_user
                  and m.status = 'active') then
      raise exception 'this person is already a member' using errcode = '22023';
    end if;
    if exists (select 1 from public.client_memberships cm
                 join public.clients c on c.id = cm.client_id
                where cm.user_id = v_user and cm.status = 'active'
                  and c.workspace_id = p_workspace_id) then
      raise exception 'a client-side member cannot become an internal member of the same workspace'
        using errcode = '22023';
    end if;
  end if;
  perform 1 from public.workspaces w where w.id = p_workspace_id for update;
  v_result := app.create_invitation(p_workspace_id, null, v_email, p_role, null,
                                    app.normalize_capabilities(p_capabilities), v_uid);
  invitation_id := v_result.invitation_id;
  token := v_result.token;
  return next;
end;
$$;

create function public.invite_client_member(
  p_client_id uuid,
  p_email text,
  p_role public.client_role,
  p_capabilities public.capability[] default '{}'
)
returns table (invitation_id uuid, token text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_workspace_id uuid := app.require_client_manager(v_uid, p_client_id);
  v_email text;
  v_user uuid;
  v_capabilities public.capability[] := app.normalize_capabilities(p_capabilities);
  v_result record;
begin
  v_email := app.require_email(p_email);
  if p_role is null then
    raise exception 'role is required' using errcode = '22023';
  end if;
  if not (v_capabilities <@ app.client_safe_capabilities()) then
    raise exception 'client memberships can only hold client-safe capabilities'
      using errcode = '22023';
  end if;
  v_user := app.user_by_email(v_email);
  if v_user is not null then
    if exists (select 1 from public.client_memberships m
                where m.client_id = p_client_id and m.user_id = v_user and m.status = 'active') then
      raise exception 'this person is already a member' using errcode = '22023';
    end if;
    if exists (select 1 from public.workspace_memberships m
                where m.workspace_id = v_workspace_id and m.user_id = v_user
                  and m.status = 'active') then
      raise exception 'an internal member cannot hold a client membership in the same workspace'
        using errcode = '22023';
    end if;
  end if;
  perform 1 from public.clients c where c.id = p_client_id for update;
  v_result := app.create_invitation(v_workspace_id, p_client_id, v_email, null, p_role,
                                    v_capabilities, v_uid);
  invitation_id := v_result.invitation_id;
  token := v_result.token;
  return next;
end;
$$;

create function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_invitation public.invitations;
begin
  select * into v_invitation from public.invitations i where i.id = p_invitation_id;
  if v_invitation.id is null then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if v_invitation.client_id is null then
    perform app.require_workspace_manager(v_uid, v_invitation.workspace_id);
  else
    perform app.require_client_manager(v_uid, v_invitation.client_id);
  end if;
  select * into v_invitation from public.invitations i where i.id = p_invitation_id for update;
  if v_invitation.status <> 'pending' then
    raise exception 'this invitation is no longer pending' using errcode = '22023';
  end if;
  update public.invitations set status = 'revoked' where id = p_invitation_id;
  perform app.audit(v_invitation.workspace_id, v_invitation.client_id, 'invitation.revoked',
                    'invitation', p_invitation_id, jsonb_build_object('status', 'pending'),
                    jsonb_build_object('status', 'revoked'));
end;
$$;

-- Accepted only by the signed-in owner of the invited, confirmed e-mail. Every refusal looks the
-- same, so a token reveals nothing about the invitation behind it.
create function public.accept_invitation(p_token text)
returns table (workspace_id uuid, client_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_invitation public.invitations;
  v_email text;
  v_confirmed timestamptz;
begin
  select * into v_invitation from public.invitations i
   where i.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     for update;
  select lower(u.email), u.email_confirmed_at into v_email, v_confirmed
    from auth.users u where u.id = v_uid;
  if v_invitation.id is null or v_invitation.status <> 'pending'
     or v_invitation.expires_at <= now() or v_email is distinct from v_invitation.email
     or v_confirmed is null then
    raise exception 'this invitation is not valid' using errcode = '22023';
  end if;

  if v_invitation.client_id is null then
    if exists (select 1 from public.client_memberships cm
                 join public.clients c on c.id = cm.client_id
                where cm.user_id = v_uid and cm.status = 'active'
                  and c.workspace_id = v_invitation.workspace_id) then
      raise exception 'a client-side member cannot become an internal member of the same workspace'
        using errcode = '22023';
    end if;
    insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status)
    values (v_invitation.workspace_id, v_uid, v_invitation.workspace_role,
            v_invitation.capabilities, 'active')
    on conflict on constraint workspace_memberships_pkey do update
       set role = excluded.role, capabilities = excluded.capabilities, status = 'active';
  else
    if exists (select 1 from public.workspace_memberships m
                where m.workspace_id = v_invitation.workspace_id and m.user_id = v_uid
                  and m.status = 'active') then
      raise exception 'an internal member cannot hold a client membership in the same workspace'
        using errcode = '22023';
    end if;
    insert into public.client_memberships (client_id, user_id, role, capabilities, status)
    values (v_invitation.client_id, v_uid, v_invitation.client_role, v_invitation.capabilities,
            'active')
    on conflict on constraint client_memberships_pkey do update
       set role = excluded.role, capabilities = excluded.capabilities, status = 'active';
  end if;

  update public.invitations
     set status = 'accepted', accepted_by = v_uid, accepted_at = now()
   where id = v_invitation.id;
  perform app.audit(v_invitation.workspace_id, v_invitation.client_id, 'invitation.accepted',
                    'invitation', v_invitation.id, jsonb_build_object('status', 'pending'),
                    jsonb_build_object('status', 'accepted', 'user_id', v_uid));
  workspace_id := v_invitation.workspace_id;
  client_id := v_invitation.client_id;
  return next;
end;
$$;

-- -----------------------------------------------------------------------------
-- Member lists for managers (e-mail comes from Auth; public.users keeps no e-mail)
-- -----------------------------------------------------------------------------
create function public.workspace_members(p_workspace_id uuid)
returns table (
  user_id uuid,
  display_name text,
  email text,
  role public.workspace_role,
  capabilities public.capability[],
  status public.membership_status
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_workspace_manager(app.require_uid(), p_workspace_id);
  return query
  select m.user_id, u.display_name, a.email::text, m.role, m.capabilities, m.status
    from public.workspace_memberships m
    join public.users u on u.id = m.user_id
    left join auth.users a on a.id = m.user_id
   where m.workspace_id = p_workspace_id
   order by m.status, lower(coalesce(a.email, ''));
end;
$$;

create function public.client_members(p_client_id uuid)
returns table (
  user_id uuid,
  display_name text,
  email text,
  role public.client_role,
  capabilities public.capability[],
  status public.membership_status
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_client_manager(app.require_uid(), p_client_id);
  return query
  select m.user_id, u.display_name, a.email::text, m.role, m.capabilities, m.status
    from public.client_memberships m
    join public.users u on u.id = m.user_id
    left join auth.users a on a.id = m.user_id
   where m.client_id = p_client_id
   order by m.status, lower(coalesce(a.email, ''));
end;
$$;

-- -----------------------------------------------------------------------------
-- Supabase Auth hook: signup only with a pending invitation (ADR 0005)
-- -----------------------------------------------------------------------------
create function public.hook_before_user_created(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_email text := app.normalize_email(event -> 'user' ->> 'email');
begin
  if v_email is not null and exists (
    select 1 from public.invitations i
     where i.email = v_email and i.status = 'pending' and i.expires_at > now()
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403, 'message', 'Cadastro somente por convite.'));
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS and privileges
-- -----------------------------------------------------------------------------
alter table public.invitations enable row level security;

create policy invitations_select_managers on public.invitations
  for select to authenticated
  using (
    case when client_id is null
         then 'workspace.manage' = any (public.workspace_capabilities(workspace_id))
         else 'client.manage' = any (public.client_capabilities(client_id))
    end
  );

revoke all on table public.invitations from anon, authenticated;
-- Every column except the token hash.
grant select (id, workspace_id, client_id, email, workspace_role, client_role, capabilities,
              status, expires_at, invited_by, accepted_by, accepted_at, created_at)
  on public.invitations to authenticated;

revoke execute on function
  app.normalize_email(text),
  app.require_email(text),
  app.user_by_email(text),
  app.create_invitation(uuid, uuid, text, public.workspace_role, public.client_role,
                        public.capability[], uuid)
from public, anon, authenticated;

revoke execute on function
  public.invite_workspace_member(uuid, text, public.workspace_role, public.capability[]),
  public.invite_client_member(uuid, text, public.client_role, public.capability[]),
  public.revoke_invitation(uuid),
  public.accept_invitation(text),
  public.workspace_members(uuid),
  public.client_members(uuid)
from public, anon;
grant execute on function
  public.invite_workspace_member(uuid, text, public.workspace_role, public.capability[]),
  public.invite_client_member(uuid, text, public.client_role, public.capability[]),
  public.revoke_invitation(uuid),
  public.accept_invitation(text),
  public.workspace_members(uuid),
  public.client_members(uuid)
to authenticated;

revoke execute on function public.hook_before_user_created(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_before_user_created(jsonb) to supabase_auth_admin;
