-- Generic security guards. They cover every current AND future object, so a migration that
-- forgets RLS, grants anon access or widens the worker role fails here.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- docs/05 §1: every exposed table is protected by RLS.
select is_empty(
  $$ select c.relname::text
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r', 'p')
        and not c.relrowsecurity $$,
  'every table in public has row level security enabled'
);

select is_empty(
  $$ select tablename || '.' || policyname
       from pg_policies
      where schemaname = 'public'
        and (btrim(coalesce(qual, '')) in ('true', '(true)')
             or btrim(coalesce(with_check, '')) in ('true', '(true)')) $$,
  'no allow-all (true) policies'
);

select is_empty(
  $$ select tablename || '.' || policyname
       from pg_policies
      where schemaname = 'public'
        and ('public' = any (roles) or 'anon' = any (roles)) $$,
  'no policy applies to anon or to every role (policies must name their role)'
);

select is_empty(
  $$ select c.relname::text
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind in ('r', 'p', 'v', 'm', 'f')
        and has_table_privilege('anon', c.oid,
              'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') $$,
  'anon has no privileges on any public table or view'
);

select is_empty(
  $$ select n.nspname || '.' || p.proname
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where p.prosecdef
        and n.nspname in ('public', 'app', 'worker')
        and not exists (
          select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'
        ) $$,
  'every SECURITY DEFINER function pins its search_path'
);

select ok(
  not has_schema_privilege('anon', 'app', 'USAGE')
  and not has_schema_privilege('anon', 'worker', 'USAGE')
  and not has_schema_privilege('authenticated', 'worker', 'USAGE'),
  'private schemas are not reachable by anon, and worker is not reachable by authenticated'
);

select set_eq(
  $$ select p.proname::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app'
        and has_function_privilege('authenticated', p.oid, 'EXECUTE') $$,
  array[
    'has_internal_client_access',
    'has_internal_workspace_access',
    'is_client_member',
    'is_internal_staff',
    'is_workspace_member'
  ],
  'authenticated may execute only the RLS predicates in schema app (explicit allowlist)'
);

select is_empty(
  $$ select p.oid::regprocedure::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('app', 'worker')
        and has_function_privilege('anon', p.oid, 'EXECUTE') $$,
  'anon cannot execute any private function'
);

-- docs/05 §1: worker paths use narrowly scoped credentials.
select ok(
  (select not rolsuper and not rolbypassrls and not rolcreaterole and not rolcreatedb
     from pg_roles where rolname = 'jmos_worker'),
  'jmos_worker is an unprivileged role (no superuser, bypassrls, createrole, createdb)'
);

select is_empty(
  $$ select n.nspname || '.' || c.relname
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in ('public', 'app', 'worker', 'auth')
        and c.relkind in ('r', 'p', 'v', 'm', 'f')
        and has_table_privilege('jmos_worker', c.oid,
              'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER') $$,
  'jmos_worker has no direct table privileges'
);

select set_eq(
  $$ select p.proname::text
       from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'worker'
        and has_function_privilege('jmos_worker', p.oid, 'EXECUTE') $$,
  array['claim_job', 'complete_job', 'extend_lease', 'fail_job', 'heartbeat'],
  'jmos_worker may execute exactly the worker API'
);

select ok(
  not has_schema_privilege('jmos_worker', 'app', 'USAGE'),
  'jmos_worker cannot reach the app schema (no enqueue, no RLS predicates)'
);

select * from finish();
rollback;
