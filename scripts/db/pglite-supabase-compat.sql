-- =============================================================================
-- Minimal emulation of the Supabase platform objects that our migrations and tests rely on.
-- Used ONLY by the PGlite fallback (JMOS_DB_MODE=pglite) when Docker is unavailable.
-- Authoritative runs use the real Supabase stack (JMOS_DB_MODE=supabase, enforced in CI).
--
-- Keep this file minimal: emulate platform behavior, never product behavior.
-- =============================================================================

-- API roles as created by Supabase.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema auth;
create schema extensions;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;

-- Subset of auth.users columns present in Supabase Auth.
create table auth.users (
  id uuid primary key,
  instance_id uuid,
  aud varchar(255),
  role varchar(255),
  email varchar(255),
  encrypted_password varchar(255),
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  created_at timestamptz,
  updated_at timestamptz,
  is_sso_user boolean not null default false,
  is_anonymous boolean not null default false
);

-- Same resolution order as Supabase's auth helpers (claims set by PostgREST per request).
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create function auth.role() returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

grant execute on function auth.uid(), auth.role(), auth.jwt() to anon, authenticated, service_role;

-- Supabase's default privileges: everything created in `public` by postgres is granted to the
-- API roles. Row Level Security plus explicit revokes in migrations must do the protecting.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
