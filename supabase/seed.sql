-- =============================================================================
-- LOCAL DEVELOPMENT SEED. Applied by `supabase db reset` / `pnpm db:reset` only.
-- Never run against production. Every credential below is a local-only development value.
--
-- Shape: one workspace ("Jansen"), two clients (A, B), internal and client users.
-- Auth identities have no password; sign-in fixtures arrive with Increment 1.
-- =============================================================================

-- Auth identities (local only). The columns are the minimal set present in Supabase Auth.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin@jansen.local', now(), now()),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'strategist@jansen.local', now(), now()),
  ('00000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'contributor@jansen.local', now(), now()),
  ('00000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'approver@cliente-a.local', now(), now()),
  ('00000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'viewer@cliente-b.local', now(), now());

insert into public.users (id, display_name)
values
  ('00000000-0000-4000-8000-000000000001', 'Admin Jansen'),
  ('00000000-0000-4000-8000-000000000002', 'Estrategista Jansen'),
  ('00000000-0000-4000-8000-000000000003', 'Colaborador Jansen'),
  ('00000000-0000-4000-8000-000000000004', 'Aprovador Cliente A'),
  ('00000000-0000-4000-8000-000000000005', 'Visualizador Cliente B');

insert into public.workspaces (id, name, slug, created_by)
values ('10000000-0000-4000-8000-000000000001', 'Jansen Company', 'jansen',
        '00000000-0000-4000-8000-000000000001');

insert into public.workspace_memberships (workspace_id, user_id, role, status)
values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'strategist', 'active'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 'contributor', 'active');

insert into public.clients (id, workspace_id, name, slug, owner_id, created_by)
values
  ('20000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000001',
   'Cliente Demo A', 'cliente-demo-a', '00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-00000000000b', '10000000-0000-4000-8000-000000000001',
   'Cliente Demo B', 'cliente-demo-b', '00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000001');

insert into public.client_memberships (client_id, user_id, role, status)
values
  ('20000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-000000000004', 'approver', 'active'),
  ('20000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-000000000005', 'viewer', 'active');

-- Local AI Worker login (see apps/ai-worker/README.md). Production sets its own secret password.
alter role jmos_worker with login password 'jmos-worker-local-dev-only';
