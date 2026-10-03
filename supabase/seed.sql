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

-- Meeting intelligence (Increment 4): a reviewed-ready meeting of Cliente Demo A. The extraction job
-- is seeded as completed so the review screen has proposals without a running worker.
insert into public.sources (id, client_id, type, title, trust_level, created_by, occurred_at) values
  ('30000000-0000-4000-8000-000000000092', '20000000-0000-4000-8000-00000000000a',
   'meeting', 'Reunião: Planejamento do trimestre', 'FIRST_PARTY',
   '00000000-0000-4000-8000-000000000002', '2026-09-28 14:00-03');
insert into public.meetings (id, client_id, title, starts_at, ends_at, participants, recording_ref,
                             transcript_source_id, processing_status, owner_id) values
  ('31000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-00000000000a',
   'Planejamento do trimestre', '2026-09-28 14:00-03', '2026-09-28 15:00-03',
   '[{"name": "Ana (Cliente Demo A)"}, {"name": "Estrategista Jansen"}]',
   'cliente-demo-a/planejamento-trimestre.m4a', '30000000-0000-4000-8000-000000000092',
   'in_review', '00000000-0000-4000-8000-000000000002');
insert into public.meeting_transcripts (meeting_id, revision, text, origin, created_by) values
  ('31000000-0000-4000-8000-000000000001', 1,
   'Ana: A partir de novembro vamos abrir aos domingos. Decidimos lançar a campanha de clareamento em novembro. Prefiro uma linguagem bem acolhedora. Talvez valha testar vídeos curtos. Vocês podem nos mandar as fotos das unidades?',
   'manual', '00000000-0000-4000-8000-000000000002');
insert into public.jobs (id, workspace_id, client_id, type, schema_version, idempotency_key, input,
                         status, attempts, model_profile, pipeline_version, result, created_by,
                         started_at, finished_at) values
  ('31000000-0000-4000-8000-0000000000a1', '10000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', 'meeting.extract', 1,
   'meeting.extract.v1:31000000-0000-4000-8000-000000000001:1',
   '{"meeting_id": "31000000-0000-4000-8000-000000000001", "transcript_revision": 1}',
   'completed', 1, 'reasoning', 'meeting.extract/1', '{"proposals": 5}',
   '00000000-0000-4000-8000-000000000002', now(), now());
insert into public.meeting_proposals (id, meeting_id, client_id, job_id, transcript_revision, kind,
                                      statement, rule_type, subject, confidence, evidence_quote) values
  ('31000000-0000-4000-8000-0000000000b1', '31000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '31000000-0000-4000-8000-0000000000a1', 1, 'fact',
   'A clínica passa a abrir aos domingos a partir de novembro.', null, null, 0.90,
   'A partir de novembro vamos abrir aos domingos'),
  ('31000000-0000-4000-8000-0000000000b2', '31000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '31000000-0000-4000-8000-0000000000a1', 1, 'decision',
   'Lançar a campanha de clareamento em novembro.', null, null, 0.85,
   'Decidimos lançar a campanha de clareamento em novembro'),
  ('31000000-0000-4000-8000-0000000000b3', '31000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '31000000-0000-4000-8000-0000000000a1', 1, 'rule',
   'Prefira uma linguagem acolhedora.', 'PREFER', 'tom', 0.70,
   'Prefiro uma linguagem bem acolhedora'),
  ('31000000-0000-4000-8000-0000000000b4', '31000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '31000000-0000-4000-8000-0000000000a1', 1, 'insight',
   'Vídeos curtos podem ser um formato a testar.', null, null, 0.40,
   'Talvez valha testar vídeos curtos'),
  ('31000000-0000-4000-8000-0000000000b5', '31000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '31000000-0000-4000-8000-0000000000a1', 1, 'task',
   'Pedir ao cliente as fotos das unidades.', null, null, 0.60,
   'Vocês podem nos mandar as fotos das unidades?');
-- Content core (Increment 5).
-- Cliente Demo A: a ready pauta with an approved post (revision 1 approved).
insert into public.pautas (id, client_id, title, status, objective, audience_ids, message, cta,
                           offer_id, source_ids, created_by) values
  ('32000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-00000000000a',
   'Avaliação gratuita para famílias', 'ready', 'Gerar agendamentos de avaliação',
   array['30000000-0000-4000-8000-000000000011']::uuid[],
   'Prevenção começa cedo: traga a família para uma avaliação.', 'Agende pelo WhatsApp',
   '30000000-0000-4000-8000-000000000021', array['30000000-0000-4000-8000-000000000041']::uuid[],
   '00000000-0000-4000-8000-000000000002');
insert into public.contents (id, client_id, pauta_id, channel, format, title, status, owner_id,
                             working_payload) values
  ('32000000-0000-4000-8000-000000000011', '20000000-0000-4000-8000-00000000000a',
   '32000000-0000-4000-8000-000000000001', 'instagram', 'post', 'Post: avaliação em família',
   'approved', '00000000-0000-4000-8000-000000000002',
   '{"headline": "Sorriso de família", "body": "Prevenção começa cedo. Traga a família para uma avaliação.", "cta": "Agende pelo WhatsApp"}');
insert into public.content_revisions (id, content_id, client_id, revision_number, payload,
                                      immutable_hash, created_by)
select '32000000-0000-4000-8000-000000000021', '32000000-0000-4000-8000-000000000011',
       '20000000-0000-4000-8000-00000000000a', 1, c.working_payload,
       encode(sha256(convert_to(c.working_payload::text, 'UTF8')), 'hex'),
       '00000000-0000-4000-8000-000000000002'
  from public.contents c where c.id = '32000000-0000-4000-8000-000000000011';
update public.contents
   set current_revision_id = '32000000-0000-4000-8000-000000000021',
       approved_revision_id = '32000000-0000-4000-8000-000000000021'
 where id = '32000000-0000-4000-8000-000000000011';

-- Cliente Demo B: a hard rule and a post waiting for internal review (rule validator demo/E2E).
insert into public.sources (id, client_id, type, title, trust_level, created_by) values
  ('32000000-0000-4000-8000-0000000000b1', '20000000-0000-4000-8000-00000000000b',
   'meeting', 'Kickoff Cliente B', 'FIRST_PARTY', '00000000-0000-4000-8000-000000000002');
insert into public.audiences (id, client_id, name, description) values
  ('32000000-0000-4000-8000-0000000000b2', '20000000-0000-4000-8000-00000000000b',
   'Empresas parceiras', 'RH de empresas da região');
insert into public.rules (id, client_id, source_id, type, subject, statement, status, proposed_by,
                          approved_by, activated_at) values
  ('32000000-0000-4000-8000-0000000000b3', '20000000-0000-4000-8000-00000000000b',
   '32000000-0000-4000-8000-0000000000b1', 'MUST_NOT', 'preco', 'Nunca divulgar preços.', 'active',
   '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', now());
insert into public.pautas (id, client_id, title, status, objective, audience_ids, angle, cta,
                           source_ids, created_by) values
  ('32000000-0000-4000-8000-0000000000b4', '20000000-0000-4000-8000-00000000000b',
   'Benefício odontológico para empresas', 'ready', 'Fechar parcerias com empresas',
   array['32000000-0000-4000-8000-0000000000b2']::uuid[],
   'Saúde bucal reduz faltas no trabalho', 'Fale com nosso time',
   array['32000000-0000-4000-8000-0000000000b1']::uuid[], '00000000-0000-4000-8000-000000000002');
insert into public.contents (id, client_id, pauta_id, channel, format, title, status, owner_id,
                             working_payload) values
  ('32000000-0000-4000-8000-0000000000b5', '20000000-0000-4000-8000-00000000000b',
   '32000000-0000-4000-8000-0000000000b4', 'linkedin', 'post', 'Post: benefício para empresas',
   'internal_review', '00000000-0000-4000-8000-000000000002',
   '{"body": "Planos corporativos a partir de R$ 29 por colaborador.", "cta": "Fale com nosso time"}');
insert into public.content_revisions (id, content_id, client_id, revision_number, payload,
                                      immutable_hash, created_by)
select '32000000-0000-4000-8000-0000000000b6', '32000000-0000-4000-8000-0000000000b5',
       '20000000-0000-4000-8000-00000000000b', 1, c.working_payload,
       encode(sha256(convert_to(c.working_payload::text, 'UTF8')), 'hex'),
       '00000000-0000-4000-8000-000000000002'
  from public.contents c where c.id = '32000000-0000-4000-8000-0000000000b5';
update public.contents set current_revision_id = '32000000-0000-4000-8000-0000000000b6'
 where id = '32000000-0000-4000-8000-0000000000b5';

-- Collaboration (Increment 6): Cliente Demo A has one post waiting for the client's approval.
insert into public.contents (id, client_id, pauta_id, channel, format, title, status, owner_id,
                             working_payload) values
  ('33000000-0000-4000-8000-000000000011', '20000000-0000-4000-8000-00000000000a',
   '32000000-0000-4000-8000-000000000001', 'instagram', 'story', 'Story: avaliação gratuita',
   'client_review', '00000000-0000-4000-8000-000000000002',
   '{"headline": "Avaliação gratuita", "body": "Neste mês, a avaliação da família é por nossa conta.", "cta": "Agende pelo WhatsApp"}');
insert into public.content_revisions (id, content_id, client_id, revision_number, payload,
                                      immutable_hash, created_by)
select '33000000-0000-4000-8000-000000000021', '33000000-0000-4000-8000-000000000011',
       '20000000-0000-4000-8000-00000000000a', 1, c.working_payload,
       encode(sha256(convert_to(c.working_payload::text, 'UTF8')), 'hex'),
       '00000000-0000-4000-8000-000000000002'
  from public.contents c where c.id = '33000000-0000-4000-8000-000000000011';
update public.contents
   set current_revision_id = '33000000-0000-4000-8000-000000000021',
       approved_revision_id = '33000000-0000-4000-8000-000000000021'
 where id = '33000000-0000-4000-8000-000000000011';
insert into public.approval_requests (id, client_id, content_id, revision_id, requested_by) values
  ('33000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-00000000000a',
   '33000000-0000-4000-8000-000000000011', '33000000-0000-4000-8000-000000000021',
   '00000000-0000-4000-8000-000000000002');

-- Calendar (Increment 7): Cliente Demo A has a client-approved post scheduled in 3 days.
insert into public.contents (id, client_id, pauta_id, channel, format, title, status, owner_id,
                             working_payload, production_due_at) values
  ('34000000-0000-4000-8000-000000000011', '20000000-0000-4000-8000-00000000000a',
   '32000000-0000-4000-8000-000000000001', 'instagram', 'post', 'Post: dicas de escovação',
   'scheduled', '00000000-0000-4000-8000-000000000002',
   '{"headline": "Escove direito", "body": "Dois minutos, duas vezes ao dia.", "cta": "Agende pelo WhatsApp"}',
   date_trunc('day', now()) + interval '1 day 18 hours');
insert into public.content_revisions (id, content_id, client_id, revision_number, payload,
                                      immutable_hash, created_by)
select '34000000-0000-4000-8000-000000000021', '34000000-0000-4000-8000-000000000011',
       '20000000-0000-4000-8000-00000000000a', 1, c.working_payload,
       encode(sha256(convert_to(c.working_payload::text, 'UTF8')), 'hex'),
       '00000000-0000-4000-8000-000000000002'
  from public.contents c where c.id = '34000000-0000-4000-8000-000000000011';
update public.contents
   set current_revision_id = '34000000-0000-4000-8000-000000000021',
       approved_revision_id = '34000000-0000-4000-8000-000000000021',
       client_approved_revision_id = '34000000-0000-4000-8000-000000000021'
 where id = '34000000-0000-4000-8000-000000000011';
insert into public.approval_requests (id, client_id, content_id, revision_id, status, requested_by,
                                      decided_at) values
  ('34000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-00000000000a',
   '34000000-0000-4000-8000-000000000011', '34000000-0000-4000-8000-000000000021', 'approved',
   '00000000-0000-4000-8000-000000000002', now());
insert into public.approval_decisions (approval_request_id, client_id, approver_user_id, decision) values
  ('34000000-0000-4000-8000-000000000031', '20000000-0000-4000-8000-00000000000a',
   '00000000-0000-4000-8000-000000000004', 'approve');
insert into public.publications (id, client_id, content_id, revision_id, channel, scheduled_at,
                                 status, created_by) values
  ('34000000-0000-4000-8000-000000000041', '20000000-0000-4000-8000-00000000000a',
   '34000000-0000-4000-8000-000000000011', '34000000-0000-4000-8000-000000000021', 'instagram',
   date_trunc('day', now()) + interval '3 days 13 hours', 'scheduled',
   '00000000-0000-4000-8000-000000000002');

-- Drive (Increment 8): Cliente Demo A has a connected folder with files from a past sync. No sync
-- job is queued, so a local worker without Drive credentials stays quiet until someone asks.
insert into public.integration_connections (id, workspace_id, client_id, provider, root_folder_id,
                                            credential_ref, last_success_at, created_by) values
  ('35000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', 'google_drive', '1DemoClienteAPastaDrive0001',
   'default', now() - interval '2 hours', '00000000-0000-4000-8000-000000000001');
insert into public.file_records (id, workspace_id, client_id, connection_id, drive_file_id, name,
                                 mime_type, drive_revision, modified_at, size_bytes) values
  ('35000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '35000000-0000-4000-8000-000000000001',
   '1DemoBriefingDoc0001', 'Briefing Cliente A.docx',
   'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'rev-1',
   now() - interval '3 days', 48213),
  ('35000000-0000-4000-8000-000000000012', '10000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '35000000-0000-4000-8000-000000000001',
   '1DemoLogoPng0002', 'Logo Cliente A.png', 'image/png', 'rev-3', now() - interval '10 days',
   183044);
insert into public.file_records (id, workspace_id, client_id, connection_id, drive_file_id, name,
                                 mime_type, drive_revision, sync_status, index_status) values
  ('35000000-0000-4000-8000-000000000013', '10000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-00000000000a', '35000000-0000-4000-8000-000000000001',
   '1DemoOldPdf0003', 'Tabela antiga.pdf', 'application/pdf', 'rev-1', 'removed', 'skipped');

-- Local AI Worker login (see apps/ai-worker/README.md). Production sets its own secret password.
alter role jmos_worker with login password 'jmos-worker-local-dev-only';
