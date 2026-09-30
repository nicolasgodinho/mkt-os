-- =============================================================================
-- Increment 0 — Tenancy kernel (Identity bounded context).
-- Spec: docs/02 §1 and §7, docs/05 §1, docs/10 "Identity" and "RLS design principle".
--
-- Security model for this migration:
--   * RLS is enabled on every table. There are no permissive `true` policies.
--   * Only SELECT policies exist. Writes are denied to `anon` and `authenticated` and happen
--     through privileged application services (Increment 1: memberships, invites, audit).
--   * Grants are explicit and do not rely on Supabase's default privileges.
--   * Access predicates live in the private schema `app`, which the Data API does not expose,
--     as SECURITY DEFINER functions with an empty search_path.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Private schema for RLS predicates and triggers
-- -----------------------------------------------------------------------------
create schema if not exists app;
comment on schema app is
  'Private helpers (RLS predicates, triggers, privileged procedures). Not exposed through the Data API.';

revoke all on schema app from public;
grant usage on schema app to authenticated;

-- Functions created in `app` are not executable unless explicitly granted.
alter default privileges in schema app revoke execute on functions from public;

-- -----------------------------------------------------------------------------
-- Enumerations (docs/01 roles/capabilities; values may be added later, never repurposed)
-- -----------------------------------------------------------------------------
create type public.workspace_status as enum ('active', 'archived');
create type public.client_status as enum ('active', 'archived');
create type public.membership_status as enum ('invited', 'active', 'revoked');

-- Internal personas (docs/01). `admin` is the Owner/Admin persona.
create type public.workspace_role as enum (
  'admin', 'account', 'strategist', 'creative', 'analyst', 'contributor'
);

-- Client personas (docs/01).
create type public.client_role as enum ('client_admin', 'approver', 'collaborator', 'viewer');

-- Core capabilities (docs/01 "Capability model"). Role defaults are resolved in Increment 1.
create type public.capability as enum (
  'workspace.manage',
  'client.manage',
  'client.view',
  'strategy.edit',
  'knowledge.propose',
  'knowledge.approve',
  'rule.activate',
  'content.create',
  'content.edit',
  'content.review_internal',
  'approval.request',
  'approval.decide',
  'publication.schedule',
  'publication.publish',
  'request.submit',
  'request.triage',
  'project.manage',
  'integration.manage',
  'audit.view',
  'admin.support'
);

-- -----------------------------------------------------------------------------
-- Shared trigger: maintain updated_at
-- -----------------------------------------------------------------------------
create function app.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- users: application profile linked 1:1 to the Supabase Auth identity
-- -----------------------------------------------------------------------------
create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.users is 'Application profile for an authenticated identity (docs/10 users).';

create trigger users_set_updated_at
  before update on public.users
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- workspaces: top-level tenant (the agency)
-- -----------------------------------------------------------------------------
create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 200),
  slug text not null unique
    check (char_length(slug) <= 64 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  status public.workspace_status not null default 'active',
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.workspaces is 'Top-level tenant (docs/02 Identity).';

create trigger workspaces_set_updated_at
  before update on public.workspaces
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- workspace_memberships: internal (Jansen) staff access to a workspace
-- -----------------------------------------------------------------------------
create table public.workspace_memberships (
  workspace_id uuid not null references public.workspaces (id),
  user_id uuid not null references public.users (id),
  role public.workspace_role not null,
  capabilities public.capability[] not null default '{}',
  status public.membership_status not null default 'invited',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
comment on table public.workspace_memberships is
  'Internal staff membership. Only status = active grants access.';

create index workspace_memberships_user_idx on public.workspace_memberships (user_id);

create trigger workspace_memberships_set_updated_at
  before update on public.workspace_memberships
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- clients: client accounts owned by a workspace
-- -----------------------------------------------------------------------------
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces (id),
  name text not null check (char_length(btrim(name)) between 1 and 200),
  slug text not null check (char_length(slug) <= 64 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  status public.client_status not null default 'active',
  owner_id uuid references public.users (id),
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, slug),
  -- Target for composite foreign keys that pin client-owned rows to the client's workspace.
  unique (id, workspace_id)
);
comment on table public.clients is 'Client account within a workspace (docs/02 Identity).';

create trigger clients_set_updated_at
  before update on public.clients
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- client_memberships: client-side users (portal) of exactly one client
-- -----------------------------------------------------------------------------
create table public.client_memberships (
  client_id uuid not null references public.clients (id),
  user_id uuid not null references public.users (id),
  role public.client_role not null,
  capabilities public.capability[] not null default '{}',
  status public.membership_status not null default 'invited',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (client_id, user_id)
);
comment on table public.client_memberships is
  'Client-side membership (portal). Only status = active grants access.';

create index client_memberships_user_idx on public.client_memberships (user_id);

create trigger client_memberships_set_updated_at
  before update on public.client_memberships
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- Access predicates (docs/05 §1). SECURITY DEFINER so they can read memberships without
-- recursive RLS evaluation. They only ever answer for the calling identity (auth.uid()).
-- -----------------------------------------------------------------------------

-- Any active internal membership in the workspace (includes contributors).
create function app.is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.workspace_memberships m
     where m.workspace_id = p_workspace_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
  );
$$;

-- Active internal membership with workspace-wide client access. Contributors are excluded
-- (fail-closed): per docs/01 they see only explicitly assigned clients, and the assignment
-- model arrives in Increment 1.
create function app.has_internal_workspace_access(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.workspace_memberships m
     where m.workspace_id = p_workspace_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
       and m.role <> 'contributor'
  );
$$;

-- Internal access to a client derives from internal access to the client's workspace.
create function app.has_internal_client_access(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select app.has_internal_workspace_access(c.workspace_id)
       from public.clients c
      where c.id = p_client_id),
    false
  );
$$;

create function app.is_client_member(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.client_memberships m
     where m.client_id = p_client_id
       and m.user_id = (select auth.uid())
       and m.status = 'active'
  );
$$;

revoke execute on function
  app.set_updated_at(),
  app.is_workspace_member(uuid),
  app.has_internal_workspace_access(uuid),
  app.has_internal_client_access(uuid),
  app.is_client_member(uuid)
from public, anon, authenticated;

grant execute on function
  app.is_workspace_member(uuid),
  app.has_internal_workspace_access(uuid),
  app.has_internal_client_access(uuid),
  app.is_client_member(uuid)
to authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.users enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_memberships enable row level security;
alter table public.clients enable row level security;
alter table public.client_memberships enable row level security;

create policy users_select_self on public.users
  for select to authenticated
  using (id = (select auth.uid()));

create policy workspaces_select_member on public.workspaces
  for select to authenticated
  using (app.is_workspace_member(id));

create policy workspace_memberships_select_own on public.workspace_memberships
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy clients_select_authorized on public.clients
  for select to authenticated
  using (app.has_internal_client_access(id) or app.is_client_member(id));

create policy client_memberships_select_own on public.client_memberships
  for select to authenticated
  using (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- Grants: read-only for signed-in users (rows filtered by RLS); nothing for anon.
-- -----------------------------------------------------------------------------
revoke all on table
  public.users,
  public.workspaces,
  public.workspace_memberships,
  public.clients,
  public.client_memberships
from anon, authenticated;

grant select on table
  public.users,
  public.workspaces,
  public.workspace_memberships,
  public.clients,
  public.client_memberships
to authenticated;
