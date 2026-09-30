-- =============================================================================
-- Increment 1 — Identity + authorization (ExecPlan 0001).
-- Contract: tests/acceptance/increment-1 (TEST_SPEC). Spec: docs/01 (capability model),
-- docs/05 §1, §2 and §6, docs/10 (Identity, Platform audit_logs).
--
-- Model: effective capabilities = role defaults ∪ explicit capabilities, for ACTIVE memberships only.
-- Writes happen only through the SECURITY DEFINER database API below. Every function:
--   1. requires an authenticated subject (auth.uid());
--   2. derives the tenant from the target row, never from caller-supplied tenant ids;
--   3. raises P0002 'not found' when the caller cannot access the target (other tenant or
--      nonexistent: indistinguishable), and 42501 'permission denied' when the target is
--      accessible but the capability is missing;
--   4. validates input (22023);
--   5. writes the change and its audit entry in one transaction.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Capability defaults (docs/01 "role defaults plus explicit capabilities")
-- -----------------------------------------------------------------------------
create function app.workspace_role_defaults(p_role public.workspace_role)
returns public.capability[]
language sql
immutable
set search_path = ''
as $$
  select case p_role
    -- Owner/Admin runs configuration, access, clients and high-impact policy.
    when 'admin' then enum_range(null::public.capability)
    when 'account' then array['client.view', 'knowledge.propose', 'approval.request',
                              'request.submit', 'request.triage', 'project.manage']::public.capability[]
    when 'strategist' then array['client.view', 'strategy.edit', 'knowledge.propose',
                                 'content.create']::public.capability[]
    when 'creative' then array['client.view', 'content.create', 'content.edit',
                               'content.review_internal']::public.capability[]
    when 'analyst' then array['client.view', 'knowledge.propose']::public.capability[]
    -- Contributor: task-scoped, nothing by default (docs/01).
    else '{}'::public.capability[]
  end;
$$;

-- Capabilities a client-side membership may ever hold (docs/01: client personas never alter
-- internal strategy, rules or configuration).
create function app.client_safe_capabilities()
returns public.capability[]
language sql
immutable
set search_path = ''
as $$
  select array['client.view', 'approval.decide', 'request.submit']::public.capability[];
$$;

create function app.client_role_defaults(p_role public.client_role)
returns public.capability[]
language sql
immutable
set search_path = ''
as $$
  select case p_role
    when 'client_admin' then array['client.view', 'approval.decide', 'request.submit']::public.capability[]
    when 'approver' then array['client.view', 'approval.decide']::public.capability[]
    when 'collaborator' then array['client.view', 'request.submit']::public.capability[]
    else array['client.view']::public.capability[]  -- viewer: read-only
  end;
$$;

create function app.normalize_capabilities(p_capabilities public.capability[])
returns public.capability[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(distinct c order by c), '{}'::public.capability[])
    from unnest(coalesce(p_capabilities, '{}'::public.capability[])) as c;
$$;

-- -----------------------------------------------------------------------------
-- Capability resolution (internal; called from SECURITY DEFINER context only)
-- -----------------------------------------------------------------------------
create function app.workspace_capabilities_of(p_user uuid, p_workspace_id uuid)
returns public.capability[]
language sql
stable
set search_path = ''
as $$
  select app.normalize_capabilities(
    (select app.workspace_role_defaults(m.role) || m.capabilities
       from public.workspace_memberships m
      where m.workspace_id = p_workspace_id
        and m.user_id = p_user
        and m.status = 'active')
  );
$$;

-- Internal members reach a client through workspace-wide `client.view` and then act with their
-- workspace capabilities. Client-side members act with their client membership capabilities.
create function app.client_capabilities_of(p_user uuid, p_client_id uuid)
returns public.capability[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_workspace_id uuid;
  v_internal public.capability[] := '{}';
  v_client_side public.capability[] := '{}';
begin
  select c.workspace_id into v_workspace_id from public.clients c where c.id = p_client_id;
  if v_workspace_id is null or p_user is null then
    return '{}';
  end if;

  v_internal := app.workspace_capabilities_of(p_user, v_workspace_id);
  if not ('client.view' = any (v_internal)) then
    v_internal := '{}';
  end if;

  select app.client_role_defaults(m.role) || m.capabilities
    into v_client_side
    from public.client_memberships m
   where m.client_id = p_client_id
     and m.user_id = p_user
     and m.status = 'active';

  return app.normalize_capabilities(v_internal || coalesce(v_client_side, '{}'));
end;
$$;

create function app.require_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  return v_uid;
end;
$$;

-- -----------------------------------------------------------------------------
-- Access predicates become capability-based (same signatures and grants as Increment 0)
-- -----------------------------------------------------------------------------
-- Workspace-wide internal access = effective `client.view` in the workspace. Contributors have
-- none by default (fail-closed); an explicit grant takes effect.
create or replace function app.has_internal_workspace_access(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select 'client.view' = any (app.workspace_capabilities_of((select auth.uid()), p_workspace_id));
$$;

create or replace function app.is_internal_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.workspace_memberships m
     where m.user_id = (select auth.uid())
       and m.status = 'active'
       and 'client.view' = any (app.workspace_role_defaults(m.role) || m.capabilities)
  );
$$;

-- -----------------------------------------------------------------------------
-- Audit trail (docs/05 §6, docs/10 Platform audit_logs): append-only
-- -----------------------------------------------------------------------------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references public.workspaces (id),
  client_id uuid,
  actor_id uuid references public.users (id),
  action text not null check (action ~ '^[a-z_]+(\.[a-z_]+)+$' and char_length(action) <= 100),
  target_type text not null check (char_length(target_type) between 1 and 50),
  target_id uuid,
  before jsonb check (before is null or jsonb_typeof(before) = 'object'),
  after jsonb check (after is null or jsonb_typeof(after) = 'object'),
  trace_id text check (char_length(trace_id) <= 100),
  created_at timestamptz not null default now(),
  constraint audit_logs_client_in_workspace
    foreign key (client_id, workspace_id) references public.clients (id, workspace_id)
);
comment on table public.audit_logs is
  'Append-only audit trail of critical actions (docs/05 §6). Written only by the database API.';

create index audit_logs_workspace_created_idx on public.audit_logs (workspace_id, created_at desc);
create index audit_logs_target_idx on public.audit_logs (target_id);

create function app.audit_logs_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_logs is append-only' using errcode = '42501';
end;
$$;

create trigger audit_logs_no_update_or_delete
  before update or delete on public.audit_logs
  for each row execute function app.audit_logs_append_only();

create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function app.audit_logs_append_only();

create function app.audit(
  p_workspace_id uuid,
  p_client_id uuid,
  p_action text,
  p_target_type text,
  p_target_id uuid,
  p_before jsonb,
  p_after jsonb
)
returns void
language sql
volatile
set search_path = ''
as $$
  insert into public.audit_logs (
    workspace_id, client_id, actor_id, action, target_type, target_id, before, after, trace_id
  )
  values (
    p_workspace_id, p_client_id, auth.uid(), p_action, p_target_type, p_target_id,
    p_before, p_after,
    left(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-request-id', 100)
  );
$$;

-- -----------------------------------------------------------------------------
-- Application profile created from the Auth identity (no e-mail copied)
-- -----------------------------------------------------------------------------
create function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, display_name)
  values (new.id, left(coalesce(btrim(new.raw_user_meta_data ->> 'display_name'), ''), 200))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_auth_user();

-- -----------------------------------------------------------------------------
-- Database API: capability reads
-- -----------------------------------------------------------------------------
create function public.workspace_capabilities(p_workspace_id uuid)
returns public.capability[]
language sql
stable
security definer
set search_path = ''
as $$
  select case when auth.uid() is null then '{}'::public.capability[]
              else app.workspace_capabilities_of(auth.uid(), p_workspace_id) end;
$$;

create function public.client_capabilities(p_client_id uuid)
returns public.capability[]
language sql
stable
security definer
set search_path = ''
as $$
  select case when auth.uid() is null then '{}'::public.capability[]
              else app.client_capabilities_of(auth.uid(), p_client_id) end;
$$;

-- Audit visibility: workspace members holding audit.view. Clients never (no workspace capability).
alter table public.audit_logs enable row level security;

create policy audit_logs_select_auditors on public.audit_logs
  for select to authenticated
  using ('audit.view' = any (public.workspace_capabilities(workspace_id)));

revoke all on table public.audit_logs from anon, authenticated;
grant select on table public.audit_logs to authenticated;

-- -----------------------------------------------------------------------------
-- Database API: clients
-- -----------------------------------------------------------------------------
create function app.assert_client_fields(p_name text, p_slug text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_name is null or char_length(btrim(p_name)) not between 1 and 200 then
    raise exception 'client name must have 1 to 200 characters' using errcode = '22023';
  end if;
  if p_slug is not null
     and (char_length(p_slug) > 64 or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$') then
    raise exception 'client slug must be lowercase words separated by hyphens' using errcode = '22023';
  end if;
end;
$$;

create function public.create_client(p_workspace_id uuid, p_name text, p_slug text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_capabilities public.capability[];
  v_client_id uuid;
begin
  if not exists (
    select 1 from public.workspace_memberships m
     where m.workspace_id = p_workspace_id and m.user_id = v_uid and m.status = 'active'
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;

  v_capabilities := app.workspace_capabilities_of(v_uid, p_workspace_id);
  if not ('client.manage' = any (v_capabilities)) then
    raise exception 'permission denied' using errcode = '42501';
  end if;

  if p_slug is null then
    raise exception 'client slug is required' using errcode = '22023';
  end if;
  perform app.assert_client_fields(p_name, p_slug);

  insert into public.clients (workspace_id, name, slug, created_by)
  values (p_workspace_id, btrim(p_name), p_slug, v_uid)
  returning id into v_client_id;

  perform app.audit(p_workspace_id, v_client_id, 'client.created', 'client', v_client_id, null,
                    jsonb_build_object('name', btrim(p_name), 'slug', p_slug));
  return v_client_id;
end;
$$;

create function public.update_client(p_client_id uuid, p_name text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_capabilities public.capability[] := app.client_capabilities_of(v_uid, p_client_id);
  v_client public.clients;
begin
  if cardinality(v_capabilities) = 0 then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not ('client.manage' = any (v_capabilities)) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  perform app.assert_client_fields(p_name, null);

  select * into v_client from public.clients c where c.id = p_client_id for update;
  update public.clients c set name = btrim(p_name) where c.id = p_client_id;

  perform app.audit(v_client.workspace_id, p_client_id, 'client.updated', 'client', p_client_id,
                    jsonb_build_object('name', v_client.name),
                    jsonb_build_object('name', btrim(p_name)));
end;
$$;

create function public.archive_client(p_client_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_capabilities public.capability[] := app.client_capabilities_of(v_uid, p_client_id);
  v_client public.clients;
begin
  if cardinality(v_capabilities) = 0 then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not ('client.manage' = any (v_capabilities)) then
    raise exception 'permission denied' using errcode = '42501';
  end if;

  select * into v_client from public.clients c where c.id = p_client_id for update;
  if v_client.status = 'archived' then
    return;
  end if;
  update public.clients c set status = 'archived' where c.id = p_client_id;

  perform app.audit(v_client.workspace_id, p_client_id, 'client.archived', 'client', p_client_id,
                    jsonb_build_object('status', v_client.status),
                    jsonb_build_object('status', 'archived'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Database API: workspace memberships (workspace.manage)
-- -----------------------------------------------------------------------------
create function app.require_workspace_manager(p_uid uuid, p_workspace_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.workspace_memberships m
     where m.workspace_id = p_workspace_id and m.user_id = p_uid and m.status = 'active'
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not ('workspace.manage' = any (app.workspace_capabilities_of(p_uid, p_workspace_id))) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
end;
$$;

-- A workspace must always keep at least one active admin.
create function app.assert_admin_remains(p_workspace_id uuid, p_leaving_user uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.workspace_memberships m
     where m.workspace_id = p_workspace_id
       and m.status = 'active'
       and m.role = 'admin'
       and m.user_id <> p_leaving_user
  ) then
    raise exception 'the workspace must keep at least one active admin' using errcode = '22023';
  end if;
end;
$$;

create function public.set_workspace_member(
  p_workspace_id uuid,
  p_user_id uuid,
  p_role public.workspace_role,
  p_capabilities public.capability[] default '{}'
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_before public.workspace_memberships;
  v_capabilities public.capability[] := app.normalize_capabilities(p_capabilities);
begin
  perform app.require_workspace_manager(v_uid, p_workspace_id);

  if p_role is null then
    raise exception 'role is required' using errcode = '22023';
  end if;
  if p_user_id = v_uid then
    raise exception 'members cannot change their own membership' using errcode = '22023';
  end if;
  if not exists (select 1 from public.users u where u.id = p_user_id) then
    raise exception 'unknown user' using errcode = '22023';
  end if;
  -- Internal and client-side identities stay separate within a workspace.
  if exists (
    select 1 from public.client_memberships cm
      join public.clients c on c.id = cm.client_id
     where cm.user_id = p_user_id and cm.status = 'active' and c.workspace_id = p_workspace_id
  ) then
    raise exception 'a client-side member cannot become an internal member of the same workspace'
      using errcode = '22023';
  end if;

  select * into v_before from public.workspace_memberships m
   where m.workspace_id = p_workspace_id and m.user_id = p_user_id
   for update;
  if v_before.status = 'active' and v_before.role = 'admin' and p_role <> 'admin' then
    perform app.assert_admin_remains(p_workspace_id, p_user_id);
  end if;

  insert into public.workspace_memberships (workspace_id, user_id, role, capabilities, status)
  values (p_workspace_id, p_user_id, p_role, v_capabilities, 'active')
  on conflict (workspace_id, user_id) do update
     set role = excluded.role, capabilities = excluded.capabilities, status = 'active';

  perform app.audit(p_workspace_id, null, 'workspace_membership.set', 'user', p_user_id,
                    case when v_before.user_id is null then null
                         else jsonb_build_object('role', v_before.role, 'capabilities',
                                                 v_before.capabilities, 'status', v_before.status) end,
                    jsonb_build_object('role', p_role, 'capabilities', v_capabilities,
                                       'status', 'active'));
end;
$$;

create function public.revoke_workspace_member(p_workspace_id uuid, p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_before public.workspace_memberships;
begin
  perform app.require_workspace_manager(v_uid, p_workspace_id);

  if p_user_id = v_uid then
    raise exception 'members cannot change their own membership' using errcode = '22023';
  end if;

  select * into v_before from public.workspace_memberships m
   where m.workspace_id = p_workspace_id and m.user_id = p_user_id
   for update;
  if v_before.user_id is null or v_before.status = 'revoked' then
    raise exception 'no membership to revoke' using errcode = '22023';
  end if;
  if v_before.status = 'active' and v_before.role = 'admin' then
    perform app.assert_admin_remains(p_workspace_id, p_user_id);
  end if;

  update public.workspace_memberships m set status = 'revoked'
   where m.workspace_id = p_workspace_id and m.user_id = p_user_id;

  perform app.audit(p_workspace_id, null, 'workspace_membership.revoked', 'user', p_user_id,
                    jsonb_build_object('role', v_before.role, 'status', v_before.status),
                    jsonb_build_object('role', v_before.role, 'status', 'revoked'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Database API: client memberships (client.manage)
-- -----------------------------------------------------------------------------
create function app.require_client_manager(p_uid uuid, p_client_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_capabilities public.capability[] := app.client_capabilities_of(p_uid, p_client_id);
begin
  if cardinality(v_capabilities) = 0 then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not ('client.manage' = any (v_capabilities)) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  return (select c.workspace_id from public.clients c where c.id = p_client_id);
end;
$$;

create function public.set_client_member(
  p_client_id uuid,
  p_user_id uuid,
  p_role public.client_role,
  p_capabilities public.capability[] default '{}'
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_workspace_id uuid := app.require_client_manager(v_uid, p_client_id);
  v_before public.client_memberships;
  v_capabilities public.capability[] := app.normalize_capabilities(p_capabilities);
begin
  if p_role is null then
    raise exception 'role is required' using errcode = '22023';
  end if;
  if not (v_capabilities <@ app.client_safe_capabilities()) then
    raise exception 'client memberships can only hold client-safe capabilities'
      using errcode = '22023';
  end if;
  if not exists (select 1 from public.users u where u.id = p_user_id) then
    raise exception 'unknown user' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.workspace_memberships m
     where m.workspace_id = v_workspace_id and m.user_id = p_user_id and m.status = 'active'
  ) then
    raise exception 'an internal member cannot hold a client membership in the same workspace'
      using errcode = '22023';
  end if;

  select * into v_before from public.client_memberships m
   where m.client_id = p_client_id and m.user_id = p_user_id
   for update;

  insert into public.client_memberships (client_id, user_id, role, capabilities, status)
  values (p_client_id, p_user_id, p_role, v_capabilities, 'active')
  on conflict (client_id, user_id) do update
     set role = excluded.role, capabilities = excluded.capabilities, status = 'active';

  perform app.audit(v_workspace_id, p_client_id, 'client_membership.set', 'user', p_user_id,
                    case when v_before.user_id is null then null
                         else jsonb_build_object('role', v_before.role, 'capabilities',
                                                 v_before.capabilities, 'status', v_before.status) end,
                    jsonb_build_object('role', p_role, 'capabilities', v_capabilities,
                                       'status', 'active'));
end;
$$;

create function public.revoke_client_member(p_client_id uuid, p_user_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_workspace_id uuid := app.require_client_manager(v_uid, p_client_id);
  v_before public.client_memberships;
begin
  select * into v_before from public.client_memberships m
   where m.client_id = p_client_id and m.user_id = p_user_id
   for update;
  if v_before.user_id is null or v_before.status = 'revoked' then
    raise exception 'no membership to revoke' using errcode = '22023';
  end if;

  update public.client_memberships m set status = 'revoked'
   where m.client_id = p_client_id and m.user_id = p_user_id;

  perform app.audit(v_workspace_id, p_client_id, 'client_membership.revoked', 'user', p_user_id,
                    jsonb_build_object('role', v_before.role, 'status', v_before.status),
                    jsonb_build_object('role', v_before.role, 'status', 'revoked'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
-- Internal helpers: never callable directly by API roles.
revoke execute on function
  app.workspace_role_defaults(public.workspace_role),
  app.client_safe_capabilities(),
  app.client_role_defaults(public.client_role),
  app.normalize_capabilities(public.capability[]),
  app.workspace_capabilities_of(uuid, uuid),
  app.client_capabilities_of(uuid, uuid),
  app.require_uid(),
  app.audit_logs_append_only(),
  app.audit(uuid, uuid, text, text, uuid, jsonb, jsonb),
  app.handle_new_auth_user(),
  app.assert_client_fields(text, text),
  app.require_workspace_manager(uuid, uuid),
  app.assert_admin_remains(uuid, uuid),
  app.require_client_manager(uuid, uuid)
from public, anon, authenticated;

-- Database API: signed-in users only (never anon; Supabase grants anon by default in public).
revoke execute on function
  public.workspace_capabilities(uuid),
  public.client_capabilities(uuid),
  public.create_client(uuid, text, text),
  public.update_client(uuid, text),
  public.archive_client(uuid),
  public.set_workspace_member(uuid, uuid, public.workspace_role, public.capability[]),
  public.revoke_workspace_member(uuid, uuid),
  public.set_client_member(uuid, uuid, public.client_role, public.capability[]),
  public.revoke_client_member(uuid, uuid)
from public, anon;

grant execute on function
  public.workspace_capabilities(uuid),
  public.client_capabilities(uuid),
  public.create_client(uuid, text, text),
  public.update_client(uuid, text),
  public.archive_client(uuid),
  public.set_workspace_member(uuid, uuid, public.workspace_role, public.capability[]),
  public.revoke_workspace_member(uuid, uuid),
  public.set_client_member(uuid, uuid, public.client_role, public.capability[]),
  public.revoke_client_member(uuid, uuid)
to authenticated;

-- Future functions in `public` are not granted to anon by the Supabase schema default.
-- (PUBLIC still gets EXECUTE by the global default: each function must revoke it explicitly,
-- which the protected acceptance tests enforce for anon.)
alter default privileges in schema public revoke execute on functions from anon;
