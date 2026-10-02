-- Increment 5 — Marketing/content core (docs/13): Initiative, Opportunity, Pauta (Definition of
-- Ready), Content, immutable ContentRevision and the deterministic rule validator.
--
-- * Everything is client-scoped, internal-only (RLS) and written only through these functions.
-- * ContentRevision is immutable (BLOCKER, docs/02): a trigger refuses UPDATE/DELETE/TRUNCATE even
--   for the table owner. Approval targets a revision, never the mutable working payload.
-- * Rule validator (docs/11 invariant 3): every effective hard rule of the content's client and
--   channel must be checked by a person for the revision under review; a MUST_NOT violation, an
--   unchecked hard rule or an open rule conflict blocks the internal approval.
-- Contract: tests/acceptance/increment-5/README.md.

create type public.initiative_kind as enum ('campaign', 'always_on', 'launch', 'activation');
create type public.initiative_status as enum (
  'draft', 'planning', 'production', 'scheduled', 'active', 'completed', 'paused', 'canceled'
);
create type public.opportunity_status as enum (
  'detected', 'reviewed', 'watching', 'dismissed', 'converted'
);
create type public.pauta_status as enum ('draft', 'ready', 'canceled');
create type public.content_status as enum (
  'idea', 'brief', 'ready', 'producing', 'internal_review', 'client_review', 'approved',
  'scheduled', 'published', 'analyzed', 'canceled', 'archived'
);
create type public.rule_check_result as enum ('pass', 'violation', 'not_applicable');

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.initiatives (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  kind public.initiative_kind not null,
  name text not null check (btrim(name) <> '' and char_length(name) <= 200),
  status public.initiative_status not null default 'draft',
  start_at date,
  end_at date,
  owner_id uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, client_id),
  check (end_at is null or start_at is null or end_at >= start_at)
);

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  initiative_id uuid,
  type text not null check (type ~ '^[a-z][a-z0-9_]{0,39}$'),
  title text not null check (btrim(title) <> '' and char_length(title) <= 300),
  reason text not null check (btrim(reason) <> '' and char_length(reason) <= 4000),
  status public.opportunity_status not null default 'detected',
  confidence numeric(3, 2) check (confidence between 0 and 1),
  expires_at timestamptz,
  evidence_refs uuid[] not null default '{}' check (cardinality(evidence_refs) <= 50),
  score_json jsonb not null default '{}'::jsonb,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, client_id),
  foreign key (initiative_id, client_id) references public.initiatives (id, client_id)
);

create table public.pautas (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  initiative_id uuid,
  opportunity_id uuid,
  title text not null check (btrim(title) <> '' and char_length(title) <= 300),
  status public.pauta_status not null default 'draft',
  objective text check (char_length(objective) <= 2000),
  audience_ids uuid[] not null default '{}' check (cardinality(audience_ids) <= 20),
  pillar text check (char_length(pillar) <= 200),
  angle text check (char_length(angle) <= 2000),
  message text check (char_length(message) <= 2000),
  cta text check (char_length(cta) <= 300),
  offer_id uuid,
  source_ids uuid[] not null default '{}' check (cardinality(source_ids) <= 50),
  mandatories text check (char_length(mandatories) <= 4000),
  constraints text check (char_length(constraints) <= 4000),
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, client_id),
  foreign key (initiative_id, client_id) references public.initiatives (id, client_id),
  foreign key (opportunity_id, client_id) references public.opportunities (id, client_id)
);

create table public.contents (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  pauta_id uuid not null,
  channel text not null check (channel ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  format text not null check (format ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  title text not null check (btrim(title) <> '' and char_length(title) <= 300),
  status public.content_status not null default 'ready',
  owner_id uuid references public.users (id),
  working_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(working_payload) = 'object' and octet_length(working_payload::text) <= 65536),
  current_revision_id uuid,
  approved_revision_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, client_id),
  foreign key (pauta_id, client_id) references public.pautas (id, client_id)
);

create table public.content_revisions (
  id uuid primary key default gen_random_uuid(),
  content_id uuid not null references public.contents (id),
  client_id uuid not null,
  revision_number integer not null check (revision_number >= 1),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  immutable_hash text not null,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  unique (content_id, revision_number),
  foreign key (content_id, client_id) references public.contents (id, client_id)
);

alter table public.contents
  add foreign key (current_revision_id) references public.content_revisions (id),
  add foreign key (approved_revision_id) references public.content_revisions (id);

create table public.content_rule_checks (
  revision_id uuid not null references public.content_revisions (id),
  rule_id uuid not null references public.rules (id),
  client_id uuid not null references public.clients (id),
  result public.rule_check_result not null,
  note text check (char_length(note) <= 1000),
  checked_by uuid references public.users (id),
  checked_at timestamptz not null default now(),
  primary key (revision_id, rule_id)
);

create trigger initiatives_updated_at before update on public.initiatives
  for each row execute function app.set_updated_at();
create trigger opportunities_updated_at before update on public.opportunities
  for each row execute function app.set_updated_at();
create trigger pautas_updated_at before update on public.pautas
  for each row execute function app.set_updated_at();
create trigger contents_updated_at before update on public.contents
  for each row execute function app.set_updated_at();

-- ContentRevision is immutable for everyone, the owner included (docs/02 BLOCKER).
create function app.content_revisions_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'content revisions are immutable' using errcode = '55000';
end;
$$;
create trigger content_revisions_no_update_or_delete
  before update or delete on public.content_revisions
  for each row execute function app.content_revisions_immutable();
create trigger content_revisions_no_truncate
  before truncate on public.content_revisions
  for each statement execute function app.content_revisions_immutable();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create function app.optional_text(p_value jsonb, p_limit integer)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_value) <> 'string' or char_length(p_value #>> '{}') > p_limit then
    raise exception 'invalid field value' using errcode = '22023';
  end if;
  return nullif(btrim(p_value #>> '{}'), '');
end;
$$;

-- uuid[] from a jsonb array, every id required to exist in the given client (P0002 otherwise).
create function app.client_refs(p_value jsonb, p_client_id uuid, p_kind text)
returns uuid[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_found integer;
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return '{}';
  end if;
  if jsonb_typeof(p_value) <> 'array' then
    raise exception 'invalid reference list' using errcode = '22023';
  end if;
  begin
    select coalesce(array_agg(distinct (e #>> '{}')::uuid), '{}') into v_ids
      from jsonb_array_elements(p_value) e;
  exception when invalid_text_representation then
    raise exception 'invalid reference list' using errcode = '22023';
  end;
  if p_kind = 'audience' then
    select count(*) into v_found from public.audiences a
     where a.id = any (v_ids) and a.client_id = p_client_id and a.status = 'active';
  else
    select count(*) into v_found from public.sources s
     where s.id = any (v_ids) and s.client_id = p_client_id;
  end if;
  if v_found <> cardinality(v_ids) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  return v_ids;
end;
$$;

-- Definition of Ready (docs/04 Content: READY requires DoR; docs/07 §7 checklist).
create function app.pauta_missing(p_pauta public.pautas)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array_remove(array[
    case when p_pauta.objective is null then 'objective' end,
    case when cardinality(p_pauta.audience_ids) = 0 then 'audience' end,
    case when p_pauta.message is null and p_pauta.angle is null then 'message_or_angle' end,
    case when p_pauta.cta is null then 'cta' end
  ], null);
$$;

-- The hard rules a revision is validated against, with their checks.
create function app.revision_rules(p_revision_id uuid)
returns table (
  rule_id uuid,
  type public.rule_type,
  subject text,
  statement text,
  result public.rule_check_result,
  blocking boolean
)
language sql
stable
set search_path = ''
as $$
  with target as (
    select r.id as revision_id, c.client_id, c.channel
      from public.content_revisions r
      join public.contents c on c.id = r.content_id
     where r.id = p_revision_id
  ),
  relevant as (
    -- Effective hard rules for the client and the content's channel ...
    select e.id, e.type, e.subject, e.statement, false as in_conflict
      from target t
      cross join lateral public.effective_rules(t.client_id, t.channel) e
     where e.type in ('MUST', 'MUST_NOT')
    union
    -- ... and every open conflict that touches the client scope or this channel.
    select r.id, r.type, r.subject, r.statement, true
      from target t
      join public.rules r on r.client_id = t.client_id
     where r.status = 'conflict'
       and (r.scope_type = 'client' or r.channel = t.channel)
  )
  select v.id, v.type, v.subject, v.statement, k.result,
         v.in_conflict or k.result is null or k.result = 'violation'
    from relevant v
    cross join target t
    left join public.content_rule_checks k
      on k.revision_id = t.revision_id and k.rule_id = v.id;
$$;

-- -----------------------------------------------------------------------------
-- Initiatives and opportunities (strategy.edit)
-- -----------------------------------------------------------------------------
create function public.create_initiative(
  p_client_id uuid,
  p_kind public.initiative_kind,
  p_name text,
  p_start_at date default null,
  p_end_at date default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'strategy.edit');
  v_name text := app.require_text(p_name, 'name');
  v_id uuid;
begin
  if p_kind is null then
    raise exception 'kind is required' using errcode = '22023';
  end if;
  if p_start_at is not null and p_end_at is not null and p_end_at < p_start_at then
    raise exception 'an initiative cannot end before it starts' using errcode = '22023';
  end if;
  insert into public.initiatives (client_id, kind, name, start_at, end_at, owner_id)
  values (p_client_id, p_kind, v_name, p_start_at, p_end_at, auth.uid())
  returning id into v_id;
  perform app.audit(v_workspace_id, p_client_id, 'initiative.created', 'initiative', v_id, null, null);
  return v_id;
end;
$$;

create function public.set_initiative_status(
  p_initiative_id uuid,
  p_status public.initiative_status
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_initiative public.initiatives;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_initiative from public.initiatives i where i.id = p_initiative_id;
  v_workspace_id := app.require_item_capability(v_initiative.client_id, 'strategy.edit');
  select * into v_initiative from public.initiatives i where i.id = p_initiative_id for update;

  -- docs/04 Initiative: DRAFT → PLANNING → PRODUCTION → SCHEDULED → ACTIVE → COMPLETED,
  -- with PAUSED (resumable) and CANCELED (terminal).
  if not (
    (v_initiative.status = 'draft' and p_status in ('planning', 'canceled'))
    or (v_initiative.status = 'planning' and p_status in ('production', 'paused', 'canceled'))
    or (v_initiative.status = 'production' and p_status in ('scheduled', 'paused', 'canceled'))
    or (v_initiative.status = 'scheduled' and p_status in ('active', 'paused', 'canceled'))
    or (v_initiative.status = 'active' and p_status in ('completed', 'paused', 'canceled'))
    or (v_initiative.status = 'paused'
        and p_status in ('planning', 'production', 'scheduled', 'active', 'canceled'))
  ) then
    raise exception 'invalid initiative transition' using errcode = '22023';
  end if;

  update public.initiatives set status = p_status where id = p_initiative_id;
  perform app.audit(v_workspace_id, v_initiative.client_id, 'initiative.status_changed',
                    'initiative', p_initiative_id, jsonb_build_object('status', v_initiative.status),
                    jsonb_build_object('status', p_status));
end;
$$;

create function public.create_opportunity(
  p_client_id uuid,
  p_type text,
  p_title text,
  p_reason text,
  p_initiative_id uuid default null,
  p_confidence numeric default null,
  p_expires_at timestamptz default null,
  p_evidence_refs uuid[] default '{}'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'strategy.edit');
  v_refs uuid[] := coalesce(p_evidence_refs, '{}');
  v_id uuid;
begin
  if p_type is null or p_type !~ '^[a-z][a-z0-9_]{0,39}$' then
    raise exception 'invalid opportunity type' using errcode = '22023';
  end if;
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then
    raise exception 'confidence must be between 0 and 1' using errcode = '22023';
  end if;
  if p_initiative_id is not null and not exists (
    select 1 from public.initiatives i where i.id = p_initiative_id and i.client_id = p_client_id
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if (select count(*) from public.sources s where s.id = any (v_refs) and s.client_id = p_client_id)
     <> cardinality(array(select distinct unnest(v_refs))) then
    raise exception 'not found' using errcode = 'P0002';
  end if;

  insert into public.opportunities (
    client_id, initiative_id, type, title, reason, confidence, expires_at, evidence_refs, created_by
  )
  values (p_client_id, p_initiative_id, p_type, app.require_text(p_title, 'title'),
          app.require_text(p_reason, 'reason'), p_confidence, p_expires_at,
          array(select distinct unnest(v_refs)), auth.uid())
  returning id into v_id;
  perform app.audit(v_workspace_id, p_client_id, 'opportunity.created', 'opportunity', v_id,
                    null, null);
  return v_id;
end;
$$;

create function public.review_opportunity(p_opportunity_id uuid, p_decision text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_opportunity public.opportunities;
  v_workspace_id uuid;
  v_next public.opportunity_status;
begin
  perform app.require_uid();
  select * into v_opportunity from public.opportunities o where o.id = p_opportunity_id;
  v_workspace_id := app.require_item_capability(v_opportunity.client_id, 'strategy.edit');
  select * into v_opportunity from public.opportunities o where o.id = p_opportunity_id for update;
  v_next := case p_decision when 'watch' then 'watching'::public.opportunity_status
                            when 'dismiss' then 'dismissed'::public.opportunity_status end;
  if v_next is null then
    raise exception 'unknown review decision' using errcode = '22023';
  end if;
  if v_opportunity.status not in ('detected', 'reviewed', 'watching') then
    raise exception 'this opportunity can no longer be reviewed' using errcode = '22023';
  end if;
  update public.opportunities set status = v_next where id = p_opportunity_id;
  perform app.audit(v_workspace_id, v_opportunity.client_id, 'opportunity.reviewed', 'opportunity',
                    p_opportunity_id, jsonb_build_object('status', v_opportunity.status),
                    jsonb_build_object('status', v_next));
end;
$$;

create function public.convert_opportunity(p_opportunity_id uuid, p_title text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_opportunity public.opportunities;
  v_workspace_id uuid;
  v_pauta_id uuid;
begin
  perform app.require_uid();
  select * into v_opportunity from public.opportunities o where o.id = p_opportunity_id;
  v_workspace_id := app.require_item_capability(v_opportunity.client_id, 'strategy.edit');
  select * into v_opportunity from public.opportunities o where o.id = p_opportunity_id for update;
  if v_opportunity.status not in ('detected', 'reviewed', 'watching') then
    raise exception 'this opportunity cannot be converted' using errcode = '22023';
  end if;

  insert into public.pautas (client_id, initiative_id, opportunity_id, title, source_ids, created_by)
  values (v_opportunity.client_id, v_opportunity.initiative_id, v_opportunity.id,
          coalesce(nullif(btrim(p_title), ''), v_opportunity.title), v_opportunity.evidence_refs,
          auth.uid())
  returning id into v_pauta_id;
  update public.opportunities set status = 'converted' where id = p_opportunity_id;

  perform app.audit(v_workspace_id, v_opportunity.client_id, 'opportunity.converted', 'opportunity',
                    p_opportunity_id, jsonb_build_object('status', v_opportunity.status),
                    jsonb_build_object('status', 'converted', 'pauta_id', v_pauta_id));
  return v_pauta_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Pautas (strategy.edit)
-- -----------------------------------------------------------------------------
create function public.create_pauta(p_client_id uuid, p_title text, p_initiative_id uuid default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'strategy.edit');
  v_id uuid;
begin
  if p_initiative_id is not null and not exists (
    select 1 from public.initiatives i where i.id = p_initiative_id and i.client_id = p_client_id
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  insert into public.pautas (client_id, initiative_id, title, created_by)
  values (p_client_id, p_initiative_id, app.require_text(p_title, 'title'), auth.uid())
  returning id into v_id;
  perform app.audit(v_workspace_id, p_client_id, 'pauta.created', 'pauta', v_id, null, null);
  return v_id;
end;
$$;

create function public.update_pauta(p_pauta_id uuid, p_fields jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pauta public.pautas;
  v_workspace_id uuid;
  v_key text;
begin
  perform app.require_uid();
  select * into v_pauta from public.pautas p where p.id = p_pauta_id;
  v_workspace_id := app.require_item_capability(v_pauta.client_id, 'strategy.edit');
  select * into v_pauta from public.pautas p where p.id = p_pauta_id for update;
  if v_pauta.status = 'canceled' then
    raise exception 'a canceled pauta cannot be edited' using errcode = '22023';
  end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then
    raise exception 'invalid fields' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_fields) loop
    if v_key not in ('title', 'objective', 'audience_ids', 'pillar', 'angle', 'message', 'cta',
                     'offer_id', 'source_ids', 'mandatories', 'constraints') then
      raise exception 'unknown pauta field' using errcode = '22023';
    end if;
  end loop;

  if p_fields ? 'title' then
    v_pauta.title := coalesce(app.optional_text(p_fields -> 'title', 300), v_pauta.title);
  end if;
  if p_fields ? 'objective' then v_pauta.objective := app.optional_text(p_fields -> 'objective', 2000); end if;
  if p_fields ? 'pillar' then v_pauta.pillar := app.optional_text(p_fields -> 'pillar', 200); end if;
  if p_fields ? 'angle' then v_pauta.angle := app.optional_text(p_fields -> 'angle', 2000); end if;
  if p_fields ? 'message' then v_pauta.message := app.optional_text(p_fields -> 'message', 2000); end if;
  if p_fields ? 'cta' then v_pauta.cta := app.optional_text(p_fields -> 'cta', 300); end if;
  if p_fields ? 'mandatories' then
    v_pauta.mandatories := app.optional_text(p_fields -> 'mandatories', 4000);
  end if;
  if p_fields ? 'constraints' then
    v_pauta.constraints := app.optional_text(p_fields -> 'constraints', 4000);
  end if;
  if p_fields ? 'audience_ids' then
    v_pauta.audience_ids := app.client_refs(p_fields -> 'audience_ids', v_pauta.client_id, 'audience');
  end if;
  if p_fields ? 'source_ids' then
    v_pauta.source_ids := app.client_refs(p_fields -> 'source_ids', v_pauta.client_id, 'source');
  end if;
  if p_fields ? 'offer_id' then
    v_pauta.offer_id := case when jsonb_typeof(p_fields -> 'offer_id') = 'null' then null
                             else (p_fields ->> 'offer_id')::uuid end;
    if v_pauta.offer_id is not null and not exists (
      select 1 from public.offers o where o.id = v_pauta.offer_id and o.client_id = v_pauta.client_id
    ) then
      raise exception 'not found' using errcode = 'P0002';
    end if;
  end if;
  -- An edit that breaks the Definition of Ready returns a ready pauta to draft.
  if v_pauta.status = 'ready' and cardinality(app.pauta_missing(v_pauta)) > 0 then
    v_pauta.status := 'draft';
  end if;

  update public.pautas p
     set title = v_pauta.title, objective = v_pauta.objective, audience_ids = v_pauta.audience_ids,
         pillar = v_pauta.pillar, angle = v_pauta.angle, message = v_pauta.message,
         cta = v_pauta.cta, offer_id = v_pauta.offer_id, source_ids = v_pauta.source_ids,
         mandatories = v_pauta.mandatories, constraints = v_pauta.constraints,
         status = v_pauta.status
   where p.id = p_pauta_id;
  perform app.audit(v_workspace_id, v_pauta.client_id, 'pauta.updated', 'pauta', p_pauta_id,
                    null, jsonb_build_object('status', v_pauta.status));
end;
$$;

create function public.pauta_readiness(p_pauta_id uuid)
returns table (field text, ok boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select f.field, not (f.field = any (app.pauta_missing(p)))
    from public.pautas p
   cross join unnest(array['objective', 'audience', 'message_or_angle', 'cta']) as f(field)
   where p.id = p_pauta_id
     and app.has_internal_client_access(p.client_id);
$$;

create function public.mark_pauta_ready(p_pauta_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pauta public.pautas;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_pauta from public.pautas p where p.id = p_pauta_id;
  v_workspace_id := app.require_item_capability(v_pauta.client_id, 'strategy.edit');
  select * into v_pauta from public.pautas p where p.id = p_pauta_id for update;
  if v_pauta.status <> 'draft' then
    raise exception 'only draft pautas can be marked ready' using errcode = '22023';
  end if;
  if cardinality(app.pauta_missing(v_pauta)) > 0 then
    raise exception 'the pauta does not meet the Definition of Ready' using errcode = '22023';
  end if;
  update public.pautas set status = 'ready' where id = p_pauta_id;
  perform app.audit(v_workspace_id, v_pauta.client_id, 'pauta.ready', 'pauta', p_pauta_id,
                    jsonb_build_object('status', 'draft'), jsonb_build_object('status', 'ready'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Content and revisions
-- -----------------------------------------------------------------------------
create function app.validate_content_payload(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or octet_length(p_payload::text) > 65536 then
    raise exception 'invalid content payload' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_payload) loop
    if v_key not in ('headline', 'body', 'cta', 'hashtags', 'alt_text') then
      raise exception 'unknown payload field' using errcode = '22023';
    end if;
    if v_key = 'hashtags' then
      if jsonb_typeof(p_payload -> 'hashtags') <> 'array'
         or jsonb_array_length(p_payload -> 'hashtags') > 30
         or exists (select 1 from jsonb_array_elements(p_payload -> 'hashtags') h
                     where jsonb_typeof(h) <> 'string' or char_length(h #>> '{}') > 100) then
        raise exception 'invalid content payload' using errcode = '22023';
      end if;
    elsif jsonb_typeof(p_payload -> v_key) <> 'string' then
      raise exception 'invalid content payload' using errcode = '22023';
    end if;
  end loop;
  return p_payload;
end;
$$;

create function public.create_content(
  p_pauta_id uuid,
  p_channel text,
  p_format text,
  p_title text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_pauta public.pautas;
  v_workspace_id uuid;
  v_channel text := lower(btrim(p_channel));
  v_format text := lower(btrim(p_format));
  v_id uuid;
begin
  perform app.require_uid();
  select * into v_pauta from public.pautas p where p.id = p_pauta_id;
  v_workspace_id := app.require_item_capability(v_pauta.client_id, 'content.create');
  if v_pauta.status <> 'ready' then
    raise exception 'content can only execute a ready pauta' using errcode = '22023';
  end if;
  if v_channel is null or v_channel !~ '^[a-z0-9][a-z0-9_-]{0,39}$'
     or v_format is null or v_format !~ '^[a-z0-9][a-z0-9_-]{0,39}$' then
    raise exception 'invalid channel or format' using errcode = '22023';
  end if;
  insert into public.contents (client_id, pauta_id, channel, format, title, owner_id)
  values (v_pauta.client_id, p_pauta_id, v_channel, v_format, app.require_text(p_title, 'title'),
          auth.uid())
  returning id into v_id;
  perform app.audit(v_workspace_id, v_pauta.client_id, 'content.created', 'content', v_id, null, null);
  return v_id;
end;
$$;

create function public.save_content_payload(p_content_id uuid, p_payload jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_content public.contents;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_content from public.contents c where c.id = p_content_id;
  v_workspace_id := app.require_item_capability(v_content.client_id, 'content.edit');
  select * into v_content from public.contents c where c.id = p_content_id for update;
  if v_content.status not in ('ready', 'producing', 'internal_review', 'approved') then
    raise exception 'this content can no longer be edited' using errcode = '22023';
  end if;
  -- Editing never touches a revision: after approval the approved revision stays as it is and
  -- the content returns to production (docs/04 Content; docs/11 invariant 2).
  update public.contents c
     set working_payload = app.validate_content_payload(p_payload), status = 'producing'
   where c.id = p_content_id;
  perform app.audit(v_workspace_id, v_content.client_id, 'content.edited', 'content', p_content_id,
                    jsonb_build_object('status', v_content.status),
                    jsonb_build_object('status', 'producing'));
end;
$$;

create function public.submit_for_internal_review(p_content_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_content public.contents;
  v_workspace_id uuid;
  v_number integer;
  v_revision_id uuid;
begin
  perform app.require_uid();
  select * into v_content from public.contents c where c.id = p_content_id;
  v_workspace_id := app.require_item_capability(v_content.client_id, 'content.edit');
  select * into v_content from public.contents c where c.id = p_content_id for update;
  if v_content.status not in ('ready', 'producing') then
    raise exception 'only content in production can be submitted' using errcode = '22023';
  end if;
  if coalesce(btrim(v_content.working_payload ->> 'body'), '') = '' then
    raise exception 'content needs a body before review' using errcode = '22023';
  end if;

  select coalesce(max(r.revision_number), 0) + 1 into v_number
    from public.content_revisions r where r.content_id = p_content_id;
  insert into public.content_revisions (
    content_id, client_id, revision_number, payload, immutable_hash, created_by
  )
  values (
    p_content_id, v_content.client_id, v_number, v_content.working_payload,
    encode(sha256(convert_to(v_content.working_payload::text, 'UTF8')), 'hex'), auth.uid()
  )
  returning id into v_revision_id;
  update public.contents
     set status = 'internal_review', current_revision_id = v_revision_id
   where id = p_content_id;

  perform app.audit(v_workspace_id, v_content.client_id, 'content.submitted', 'content_revision',
                    v_revision_id, null, jsonb_build_object('revision_number', v_number));
  return v_revision_id;
end;
$$;

-- Locks the content of a revision under internal review that the caller may review.
create function app.require_reviewable_revision(p_revision_id uuid, out content public.contents,
                                                out workspace_id uuid)
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_client_id uuid;
begin
  perform app.require_uid();
  select r.client_id into v_client_id from public.content_revisions r where r.id = p_revision_id;
  workspace_id := app.require_item_capability(v_client_id, 'content.review_internal');
  select c.* into content
    from public.contents c join public.content_revisions r on r.content_id = c.id
   where r.id = p_revision_id
     for update of c;
  if content.status <> 'internal_review' or content.current_revision_id <> p_revision_id then
    raise exception 'this revision is not under internal review' using errcode = '22023';
  end if;
end;
$$;

create function public.record_rule_check(
  p_revision_id uuid,
  p_rule_id uuid,
  p_result public.rule_check_result,
  p_note text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope record := app.require_reviewable_revision(p_revision_id);
  v_content public.contents := v_scope.content;
begin
  if not exists (
    select 1 from public.rules r where r.id = p_rule_id and r.client_id = v_content.client_id
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if p_result is null
     or not exists (select 1 from app.revision_rules(p_revision_id) v where v.rule_id = p_rule_id) then
    raise exception 'only the hard rules of this revision can be checked' using errcode = '22023';
  end if;
  if char_length(p_note) > 1000 then
    raise exception 'note is too long' using errcode = '22023';
  end if;

  insert into public.content_rule_checks (revision_id, rule_id, client_id, result, note, checked_by)
  values (p_revision_id, p_rule_id, v_content.client_id, p_result, nullif(btrim(p_note), ''),
          auth.uid())
  on conflict (revision_id, rule_id) do update
     set result = excluded.result, note = excluded.note, checked_by = excluded.checked_by,
         checked_at = now();
  perform app.audit(v_scope.workspace_id, v_content.client_id, 'content.rule_checked',
                    'content_revision', p_revision_id, null,
                    jsonb_build_object('rule_id', p_rule_id, 'result', p_result));
end;
$$;

create function public.revision_validation(p_revision_id uuid)
returns table (
  rule_id uuid,
  type public.rule_type,
  subject text,
  statement text,
  result public.rule_check_result,
  blocking boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select v.*
    from app.revision_rules(p_revision_id) v
   where exists (
     select 1 from public.content_revisions r
      where r.id = p_revision_id and app.has_internal_client_access(r.client_id)
   );
$$;

create function public.complete_internal_review(
  p_revision_id uuid,
  p_decision text,
  p_note text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope record := app.require_reviewable_revision(p_revision_id);
  v_content public.contents := v_scope.content;
begin
  if p_decision not in ('approve', 'changes') or p_decision is null then
    raise exception 'unknown review decision' using errcode = '22023';
  end if;
  if p_decision = 'approve' then
    if exists (select 1 from app.revision_rules(p_revision_id) v where v.blocking) then
      raise exception 'content has blocking rule checks' using errcode = '22023';
    end if;
    update public.contents
       set status = 'approved', approved_revision_id = p_revision_id
     where id = v_content.id;
  else
    update public.contents set status = 'producing' where id = v_content.id;
  end if;
  perform app.audit(v_scope.workspace_id, v_content.client_id,
                    case p_decision when 'approve' then 'content.internal_approved'
                                    else 'content.changes_requested' end,
                    'content_revision', p_revision_id,
                    jsonb_build_object('status', 'internal_review'),
                    jsonb_build_object('decision', p_decision,
                                       'note', left(nullif(btrim(p_note), ''), 500)));
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS and privileges
-- -----------------------------------------------------------------------------
alter table public.initiatives enable row level security;
alter table public.opportunities enable row level security;
alter table public.pautas enable row level security;
alter table public.contents enable row level security;
alter table public.content_revisions enable row level security;
alter table public.content_rule_checks enable row level security;

create policy initiatives_select_internal on public.initiatives
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy opportunities_select_internal on public.opportunities
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy pautas_select_internal on public.pautas
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy contents_select_internal on public.contents
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy content_revisions_select_internal on public.content_revisions
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy content_rule_checks_select_internal on public.content_rule_checks
  for select to authenticated using (app.has_internal_client_access(client_id));

revoke all on table public.initiatives, public.opportunities, public.pautas, public.contents,
  public.content_revisions, public.content_rule_checks from anon, authenticated;
grant select on table public.initiatives, public.opportunities, public.pautas, public.contents,
  public.content_revisions, public.content_rule_checks to authenticated;

revoke execute on function
  app.content_revisions_immutable(),
  app.optional_text(jsonb, integer),
  app.client_refs(jsonb, uuid, text),
  app.pauta_missing(public.pautas),
  app.revision_rules(uuid),
  app.validate_content_payload(jsonb),
  app.require_reviewable_revision(uuid)
from public, anon, authenticated;

revoke execute on function
  public.create_initiative(uuid, public.initiative_kind, text, date, date),
  public.set_initiative_status(uuid, public.initiative_status),
  public.create_opportunity(uuid, text, text, text, uuid, numeric, timestamptz, uuid[]),
  public.review_opportunity(uuid, text),
  public.convert_opportunity(uuid, text),
  public.create_pauta(uuid, text, uuid),
  public.update_pauta(uuid, jsonb),
  public.pauta_readiness(uuid),
  public.mark_pauta_ready(uuid),
  public.create_content(uuid, text, text, text),
  public.save_content_payload(uuid, jsonb),
  public.submit_for_internal_review(uuid),
  public.record_rule_check(uuid, uuid, public.rule_check_result, text),
  public.revision_validation(uuid),
  public.complete_internal_review(uuid, text, text)
from public, anon;
grant execute on function
  public.create_initiative(uuid, public.initiative_kind, text, date, date),
  public.set_initiative_status(uuid, public.initiative_status),
  public.create_opportunity(uuid, text, text, text, uuid, numeric, timestamptz, uuid[]),
  public.review_opportunity(uuid, text),
  public.convert_opportunity(uuid, text),
  public.create_pauta(uuid, text, uuid),
  public.update_pauta(uuid, jsonb),
  public.pauta_readiness(uuid),
  public.mark_pauta_ready(uuid),
  public.create_content(uuid, text, text, text),
  public.save_content_payload(uuid, jsonb),
  public.submit_for_internal_review(uuid),
  public.record_rule_check(uuid, uuid, public.rule_check_result, text),
  public.revision_validation(uuid),
  public.complete_internal_review(uuid, text, text)
to authenticated;
