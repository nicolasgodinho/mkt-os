-- =============================================================================
-- LOCAL DEVELOPMENT / CI SEED. Applied by `supabase db reset` / `pnpm db:reset` only.
-- Never run against production or any network-reachable database (see DEVELOPMENT.md).
-- Every credential below is a local-only development value.
--
-- Sign-in password for every seeded identity: jmos-local-dev-password
--
-- Workspace "Jansen Company" (slug jansen)
--   admin@jansen.local            admin (Owner/Admin)
--   strategist@jansen.local       strategist
--   contributor@jansen.local      contributor (no client access until explicitly granted)
--   revoked@jansen.local          strategist, membership REVOKED
--   Cliente Demo A: client-admin@cliente-a.local (client_admin), approver@cliente-a.local
--                   (approver), collaborator@cliente-a.local (collaborator),
--                   revoked@cliente-a.local (viewer, REVOKED)
--   Cliente Demo B: viewer@cliente-b.local (viewer)
-- Workspace "Agência Alternativa" (slug outra-agencia)
--   admin@outra-agencia.local     admin
--   Cliente Alternativo C: viewer@cliente-c.local (viewer)
-- =============================================================================

-- Auth identities. With real Supabase Auth (GoTrue), users need a password hash, empty token
-- columns and an e-mail identity to sign in. The PGlite fallback has only a minimal auth.users
-- table (see scripts/db/pglite-supabase-compat.sql). Profiles in public.users are created by the
-- on_auth_user_created trigger.
do $$
declare
  v_gotrue boolean := to_regclass('auth.identities') is not null;
  v_password constant text := 'jmos-local-dev-password';
  r record;
begin
  for r in
    select * from (values
      ('00000000-0000-4000-8000-000000000001'::uuid, 'admin@jansen.local', 'Admin Jansen'),
      ('00000000-0000-4000-8000-000000000002'::uuid, 'strategist@jansen.local', 'Estrategista Jansen'),
      ('00000000-0000-4000-8000-000000000003'::uuid, 'contributor@jansen.local', 'Colaborador Jansen'),
      ('00000000-0000-4000-8000-000000000004'::uuid, 'approver@cliente-a.local', 'Aprovador Cliente A'),
      ('00000000-0000-4000-8000-000000000005'::uuid, 'viewer@cliente-b.local', 'Visualizador Cliente B'),
      ('00000000-0000-4000-8000-000000000006'::uuid, 'revoked@jansen.local', 'Ex-membro Jansen'),
      ('00000000-0000-4000-8000-000000000007'::uuid, 'client-admin@cliente-a.local', 'Admin Cliente A'),
      ('00000000-0000-4000-8000-000000000008'::uuid, 'collaborator@cliente-a.local', 'Colaborador Cliente A'),
      ('00000000-0000-4000-8000-000000000009'::uuid, 'revoked@cliente-a.local', 'Ex-membro Cliente A'),
      ('00000000-0000-4000-8000-00000000000a'::uuid, 'admin@outra-agencia.local', 'Admin Outra Agência'),
      ('00000000-0000-4000-8000-00000000000b'::uuid, 'viewer@cliente-c.local', 'Visualizador Cliente C')
    ) as t(id, email, display_name)
  loop
    if v_gotrue then
      execute $sql$
        insert into auth.users (
          instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
          confirmation_token, recovery_token, email_change_token_new, email_change,
          email_change_token_current, phone_change, phone_change_token, reauthentication_token
        ) values (
          '00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2,
          extensions.crypt($3, extensions.gen_salt('bf')), now(),
          '{"provider": "email", "providers": ["email"]}'::jsonb,
          jsonb_build_object('display_name', $4), now(), now(),
          '', '', '', '', '', '', '', ''
        )
      $sql$ using r.id, r.email, v_password, r.display_name;
      execute $sql$
        insert into auth.identities (
          id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
        ) values (
          gen_random_uuid(), $1, $1::text,
          jsonb_build_object('sub', $1::text, 'email', $2, 'email_verified', true),
          'email', now(), now(), now()
        )
      $sql$ using r.id, r.email;
    else
      insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
      values (r.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
              r.email, jsonb_build_object('display_name', r.display_name), now(), now());
    end if;
  end loop;
end;
$$;

insert into public.workspaces (id, name, slug, created_by) values
  ('10000000-0000-4000-8000-000000000001', 'Jansen Company', 'jansen',
   '00000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002', 'Agência Alternativa', 'outra-agencia',
   '00000000-0000-4000-8000-00000000000a');

insert into public.workspace_memberships (workspace_id, user_id, role, status) values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'admin', 'active'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', 'strategist', 'active'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 'contributor', 'active'),
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000006', 'strategist', 'revoked'),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-00000000000a', 'admin', 'active');

insert into public.clients (id, workspace_id, name, slug, owner_id, created_by) values
  ('20000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000001',
   'Cliente Demo A', 'cliente-demo-a', '00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-00000000000b', '10000000-0000-4000-8000-000000000001',
   'Cliente Demo B', 'cliente-demo-b', '00000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-00000000000c', '10000000-0000-4000-8000-000000000002',
   'Cliente Alternativo C', 'cliente-alternativo-c', null,
   '00000000-0000-4000-8000-00000000000a');

insert into public.client_memberships (client_id, user_id, role, status) values
  ('20000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-000000000004', 'approver', 'active'),
  ('20000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-000000000007', 'client_admin', 'active'),
  ('20000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-000000000008', 'collaborator', 'active'),
  ('20000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-000000000009', 'viewer', 'revoked'),
  ('20000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-000000000005', 'viewer', 'active'),
  ('20000000-0000-4000-8000-00000000000c', '00000000-0000-4000-8000-00000000000b', 'viewer', 'active');

-- Client Brain of Cliente Demo A (Increment 2). Seeded directly; the app only writes through the
-- database API, where everything enters as proposed and is approved by a human.
insert into public.brand_profiles (id, client_id, business, brand, voice, visual_references, updated_by) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-00000000000a',
   'Clínica odontológica familiar com três unidades.',
   'Acolhedora, confiável e sem jargão.',
   'Próxima, didática e positiva. Trata o leitor por "você".',
   array['https://example.test/cliente-a/moodboard'],
   '00000000-0000-4000-8000-000000000002');

insert into public.audiences (id, client_id, name, description) values
  ('30000000-0000-4000-8000-000000000011', '20000000-0000-4000-8000-00000000000a',
   'Famílias com crianças', 'Pais de 28 a 45 anos que buscam prevenção para os filhos.');
insert into public.offers (id, client_id, name, description, valid_from, valid_until) values
  ('30000000-0000-4000-8000-000000000021', '20000000-0000-4000-8000-00000000000a',
   'Avaliação gratuita', 'Primeira consulta de avaliação sem custo.', '2026-01-01', '2026-12-31');
insert into public.regions (id, client_id, name, description) values
  ('30000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-00000000000a',
   'Grande São Paulo', 'Unidades em Pinheiros, Moema e Santo André.');

insert into public.sources (id, client_id, type, title, trust_level, uri, created_by) values
  ('30000000-0000-4000-8000-000000000041', '20000000-0000-4000-8000-00000000000a',
   'meeting', 'Reunião de kickoff', 'FIRST_PARTY', null, '00000000-0000-4000-8000-000000000002'),
  ('30000000-0000-4000-8000-000000000042', '20000000-0000-4000-8000-00000000000a',
   'website', 'Comentário em fórum', 'UNTRUSTED_EXTERNAL', 'https://example.test/forum/123',
   '00000000-0000-4000-8000-000000000002');

insert into public.facts (id, client_id, source_id, statement, status, proposed_by, approved_by) values
  ('30000000-0000-4000-8000-000000000051', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000041', 'Atende de segunda a sábado.', 'active',
   '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000052', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000041', 'Vai abrir uma unidade em Campinas em 2027.', 'proposed',
   '00000000-0000-4000-8000-000000000002', null);
insert into public.decisions (id, client_id, source_id, statement, rationale, owner_id, status, approved_by) values
  ('30000000-0000-4000-8000-000000000061', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000041', 'Priorizar Instagram e LinkedIn em 2026.',
   'Onde está o público de famílias e de empresas parceiras.', '00000000-0000-4000-8000-000000000002',
   'active', '00000000-0000-4000-8000-000000000001');
insert into public.insights (id, client_id, source_id, statement, confidence, proposed_by) values
  ('30000000-0000-4000-8000-000000000071', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000042', 'Pacientes associam a marca a atendimento rápido.', 0.40,
   '00000000-0000-4000-8000-000000000002');

insert into public.rules (id, client_id, source_id, type, subject, statement, status, proposed_by, approved_by, activated_at) values
  ('30000000-0000-4000-8000-000000000081', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000041', 'MUST', 'cta',
   'Todo post termina com uma chamada para ação.', 'active',
   '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', now()),
  ('30000000-0000-4000-8000-000000000082', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000041', 'PREFER', null,
   'Prefira frases curtas e voz ativa.', 'active',
   '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', now()),
  ('30000000-0000-4000-8000-000000000083', '20000000-0000-4000-8000-00000000000a',
   '30000000-0000-4000-8000-000000000041', 'MUST_NOT', 'preco',
   'Não divulgar preços de tratamentos.', 'proposed',
   '00000000-0000-4000-8000-000000000002', null, null);

-- Local AI Worker login (see apps/ai-worker/README.md). Production sets its own secret password.
alter role jmos_worker with login password 'jmos-worker-local-dev-only';
