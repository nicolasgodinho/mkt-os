-- Increment 2 — Client Brain basics (docs/13): strategy context, sources, knowledge, rules.
--
-- * Every table is client-scoped, readable only by internal staff with access to the client
--   (RLS), and never writable directly: all writes go through SECURITY DEFINER functions.
-- * Knowledge always enters as `proposed`; approval/activation is a separate audited step.
-- * Untrusted sources never become Facts, Decisions or Rules (docs/02 §5).
-- * Hard-rule conflicts are structural (same client/scope/subject/priority, opposite polarity,
--   overlapping validity) and leave both rules out of the effective set until a human resolves
--   them (docs/02 §4).
-- Contract: tests/acceptance/increment-2/README.md.

-- -----------------------------------------------------------------------------
-- Types
-- -----------------------------------------------------------------------------
create type public.context_status as enum ('active', 'archived');
create type public.source_type as enum (
  'document', 'meeting', 'website', 'analytics', 'review', 'social_post', 'user_input'
);
create type public.source_trust as enum (
  'SYSTEM', 'APPROVED_CLIENT', 'FIRST_PARTY', 'TRUSTED_EXTERNAL', 'UNTRUSTED_EXTERNAL'
);
create type public.knowledge_kind as enum ('fact', 'decision', 'insight');
create type public.knowledge_status as enum ('proposed', 'active', 'rejected');
create type public.rule_type as enum ('MUST', 'MUST_NOT', 'PREFER', 'AVOID');
create type public.rule_scope as enum ('client', 'channel');
create type public.rule_status as enum (
  'proposed', 'active', 'superseded', 'rejected', 'expired', 'conflict'
);

-- -----------------------------------------------------------------------------
-- Strategy context
-- -----------------------------------------------------------------------------
create table public.brand_profiles (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique references public.clients (id),
  business text not null default '' check (char_length(business) <= 4000),
  brand text not null default '' check (char_length(brand) <= 4000),
  voice text not null default '' check (char_length(voice) <= 4000),
  visual_references text[] not null default '{}'
    check (cardinality(visual_references) <= 50
           and char_length(array_to_string(visual_references, '')) <= 50 * 2000),
  updated_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audiences (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  name text not null check (btrim(name) <> '' and char_length(name) <= 200),
  description text not null default '' check (char_length(description) <= 2000),
  status public.context_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index audiences_client_idx on public.audiences (client_id);

create table public.offers (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  name text not null check (btrim(name) <> '' and char_length(name) <= 200),
  description text not null default '' check (char_length(description) <= 2000),
  valid_from date,
  valid_until date,
  status public.context_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (valid_until is null or valid_from is null or valid_until >= valid_from)
);
create index offers_client_idx on public.offers (client_id);

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  name text not null check (btrim(name) <> '' and char_length(name) <= 200),
  description text not null default '' check (char_length(description) <= 2000),
  status public.context_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index regions_client_idx on public.regions (client_id);

-- -----------------------------------------------------------------------------
-- Knowledge
-- -----------------------------------------------------------------------------
create table public.sources (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  type public.source_type not null,
  title text not null check (btrim(title) <> '' and char_length(title) <= 300),
  trust_level public.source_trust not null check (trust_level <> 'SYSTEM'),
  uri text check (char_length(uri) <= 2000),
  occurred_at timestamptz,
  metadata jsonb not null default '{}',
  created_by uuid not null references public.users (id),
  created_at timestamptz not null default now(),
  unique (id, client_id)
);
create index sources_client_idx on public.sources (client_id);

create table public.facts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  source_id uuid not null,
  statement text not null check (btrim(statement) <> '' and char_length(statement) <= 2000),
  status public.knowledge_status not null default 'proposed',
  valid_from timestamptz,
  valid_until timestamptz,
  proposed_by uuid not null references public.users (id),
  approved_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (source_id, client_id) references public.sources (id, client_id),
  check (valid_until is null or valid_from is null or valid_until > valid_from)
);
create index facts_client_idx on public.facts (client_id, status);

create table public.decisions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  source_id uuid not null,
  statement text not null check (btrim(statement) <> '' and char_length(statement) <= 2000),
  rationale text check (char_length(rationale) <= 2000),
  decided_at timestamptz not null default now(),
  owner_id uuid not null references public.users (id),
  status public.knowledge_status not null default 'proposed',
  approved_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (source_id, client_id) references public.sources (id, client_id)
);
create index decisions_client_idx on public.decisions (client_id, status);

create table public.insights (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  source_id uuid not null,
  statement text not null check (btrim(statement) <> '' and char_length(statement) <= 2000),
  confidence numeric(3, 2) check (confidence between 0 and 1),
  status public.knowledge_status not null default 'proposed',
  proposed_by uuid not null references public.users (id),
  approved_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (source_id, client_id) references public.sources (id, client_id)
);
create index insights_client_idx on public.insights (client_id, status);

create table public.rules (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  source_id uuid not null,
  type public.rule_type not null,
  subject text check (subject is null or (subject = lower(btrim(subject)) and subject <> ''
                                         and char_length(subject) <= 80)),
  statement text not null check (btrim(statement) <> '' and char_length(statement) <= 2000),
  scope_type public.rule_scope not null default 'client',
  channel text check (channel is null or channel ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  priority integer not null default 50 check (priority between 0 and 100),
  status public.rule_status not null default 'proposed',
  effective_from timestamptz,
  effective_until timestamptz,
  exception_expression text check (char_length(exception_expression) <= 2000),
  supersedes_rule_id uuid,
  proposed_by uuid not null references public.users (id),
  approved_by uuid references public.users (id),
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, client_id),
  foreign key (source_id, client_id) references public.sources (id, client_id),
  foreign key (supersedes_rule_id, client_id) references public.rules (id, client_id),
  check ((scope_type = 'channel') = (channel is not null)),
  check (type not in ('MUST', 'MUST_NOT') or subject is not null),
  check (effective_until is null or effective_from is null or effective_until > effective_from)
);
create index rules_client_subject_idx on public.rules (client_id, subject, status);

create trigger brand_profiles_updated_at before update on public.brand_profiles
  for each row execute function app.set_updated_at();
create trigger audiences_updated_at before update on public.audiences
  for each row execute function app.set_updated_at();
create trigger offers_updated_at before update on public.offers
  for each row execute function app.set_updated_at();
create trigger regions_updated_at before update on public.regions
  for each row execute function app.set_updated_at();
create trigger facts_updated_at before update on public.facts
  for each row execute function app.set_updated_at();
create trigger decisions_updated_at before update on public.decisions
  for each row execute function app.set_updated_at();
create trigger insights_updated_at before update on public.insights
  for each row execute function app.set_updated_at();
create trigger rules_updated_at before update on public.rules
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------
-- Capabilities of the caller on a client that must be visible to them (P0002 otherwise).
create function app.require_client_capability(p_client_id uuid, p_capability public.capability)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_capabilities public.capability[] :=
    app.client_capabilities_of(app.require_uid(), p_client_id);
  v_workspace_id uuid;
begin
  if cardinality(v_capabilities) = 0 then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not (p_capability = any (v_capabilities)) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select c.workspace_id into v_workspace_id from public.clients c where c.id = p_client_id;
  return v_workspace_id;
end;
$$;

-- Same, for an existing Client Brain item: only internal staff can read items (P0002 otherwise).
create function app.require_item_capability(p_client_id uuid, p_capability public.capability)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_workspace_id uuid;
begin
  if p_client_id is null or not app.has_internal_client_access(p_client_id) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if not (p_capability = any (app.client_capabilities_of(v_uid, p_client_id))) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select c.workspace_id into v_workspace_id from public.clients c where c.id = p_client_id;
  return v_workspace_id;
end;
$$;

create function app.require_text(p_value text, p_field text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null or btrim(p_value) = '' then
    raise exception '% is required', p_field using errcode = '22023';
  end if;
  return btrim(p_value);
end;
$$;

-- A source of the given client, or P0002. Returns its trust level.
create function app.client_source_trust(p_client_id uuid, p_source_id uuid)
returns public.source_trust
language plpgsql
stable
set search_path = ''
as $$
declare
  v_trust public.source_trust;
begin
  if p_source_id is null then
    raise exception 'source is required' using errcode = '22023';
  end if;
  select s.trust_level into v_trust
    from public.sources s
   where s.id = p_source_id and s.client_id = p_client_id;
  if v_trust is null then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  return v_trust;
end;
$$;

-- Recomputes structural conflicts among active/conflicting hard rules of one subject.
create function app.recompute_rule_conflicts(p_workspace_id uuid, p_client_id uuid, p_subject text)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_rule record;
begin
  if p_subject is null then
    return;
  end if;
  for v_rule in
    select r.id, r.status,
           case when exists (
             select 1
               from public.rules o
              where o.client_id = r.client_id
                and o.id <> r.id
                and o.subject = r.subject
                and o.status in ('active', 'conflict')
                and o.type = case r.type when 'MUST' then 'MUST_NOT'::public.rule_type
                                         else 'MUST'::public.rule_type end
                and o.scope_type = r.scope_type
                and o.channel is not distinct from r.channel
                and o.priority = r.priority
                and tstzrange(o.effective_from, o.effective_until, '[)')
                    && tstzrange(r.effective_from, r.effective_until, '[)')
           ) then 'conflict'::public.rule_status else 'active'::public.rule_status end as next_status
      from public.rules r
     where r.client_id = p_client_id
       and r.subject = p_subject
       and r.type in ('MUST', 'MUST_NOT')
       and r.status in ('active', 'conflict')
  loop
    if v_rule.next_status <> v_rule.status then
      update public.rules set status = v_rule.next_status where id = v_rule.id;
      perform app.audit(p_workspace_id, p_client_id,
                        case v_rule.next_status when 'conflict' then 'rule.conflict_detected'
                                                else 'rule.conflict_resolved' end,
                        'rule', v_rule.id,
                        jsonb_build_object('status', v_rule.status),
                        jsonb_build_object('status', v_rule.next_status));
    end if;
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Database API: strategy context (strategy.edit)
-- -----------------------------------------------------------------------------
create function public.save_brand_profile(
  p_client_id uuid,
  p_business text,
  p_brand text,
  p_voice text,
  p_visual_references text[]
)
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
  insert into public.brand_profiles as b
    (client_id, business, brand, voice, visual_references, updated_by)
  values (p_client_id, coalesce(btrim(p_business), ''), coalesce(btrim(p_brand), ''),
          coalesce(btrim(p_voice), ''), coalesce(p_visual_references, '{}'), auth.uid())
  on conflict (client_id) do update
    set business = excluded.business,
        brand = excluded.brand,
        voice = excluded.voice,
        visual_references = excluded.visual_references,
        updated_by = excluded.updated_by
  returning b.id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'brand_profile.saved', 'brand_profile', v_id,
                    null, null);
  return v_id;
end;
$$;

create function public.save_audience(
  p_client_id uuid,
  p_audience_id uuid,
  p_name text,
  p_description text
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
  if p_audience_id is null then
    insert into public.audiences (client_id, name, description)
    values (p_client_id, v_name, coalesce(btrim(p_description), ''))
    returning id into v_id;
  else
    update public.audiences a
       set name = v_name, description = coalesce(btrim(p_description), '')
     where a.id = p_audience_id and a.client_id = p_client_id
    returning a.id into v_id;
    if v_id is null then
      raise exception 'not found' using errcode = 'P0002';
    end if;
  end if;

  perform app.audit(v_workspace_id, p_client_id, 'audience.saved', 'audience', v_id, null, null);
  return v_id;
end;
$$;

create function public.save_offer(
  p_client_id uuid,
  p_offer_id uuid,
  p_name text,
  p_description text,
  p_valid_from date,
  p_valid_until date
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
  if p_valid_from is not null and p_valid_until is not null and p_valid_until < p_valid_from then
    raise exception 'offer validity ends before it starts' using errcode = '22023';
  end if;
  if p_offer_id is null then
    insert into public.offers (client_id, name, description, valid_from, valid_until)
    values (p_client_id, v_name, coalesce(btrim(p_description), ''), p_valid_from, p_valid_until)
    returning id into v_id;
  else
    update public.offers o
       set name = v_name, description = coalesce(btrim(p_description), ''),
           valid_from = p_valid_from, valid_until = p_valid_until
     where o.id = p_offer_id and o.client_id = p_client_id
    returning o.id into v_id;
    if v_id is null then
      raise exception 'not found' using errcode = 'P0002';
    end if;
  end if;

  perform app.audit(v_workspace_id, p_client_id, 'offer.saved', 'offer', v_id, null, null);
  return v_id;
end;
$$;

create function public.save_region(
  p_client_id uuid,
  p_region_id uuid,
  p_name text,
  p_description text
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
  if p_region_id is null then
    insert into public.regions (client_id, name, description)
    values (p_client_id, v_name, coalesce(btrim(p_description), ''))
    returning id into v_id;
  else
    update public.regions r
       set name = v_name, description = coalesce(btrim(p_description), '')
     where r.id = p_region_id and r.client_id = p_client_id
    returning r.id into v_id;
    if v_id is null then
      raise exception 'not found' using errcode = 'P0002';
    end if;
  end if;

  perform app.audit(v_workspace_id, p_client_id, 'region.saved', 'region', v_id, null, null);
  return v_id;
end;
$$;

create function public.archive_context_item(p_kind text, p_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_client_id uuid;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  if p_kind is null or p_kind not in ('audience', 'offer', 'region') then
    raise exception 'unknown context kind' using errcode = '22023';
  end if;

  if p_kind = 'audience' then
    select a.client_id into v_client_id from public.audiences a where a.id = p_id;
  elsif p_kind = 'offer' then
    select o.client_id into v_client_id from public.offers o where o.id = p_id;
  else
    select r.client_id into v_client_id from public.regions r where r.id = p_id;
  end if;
  v_workspace_id := app.require_item_capability(v_client_id, 'strategy.edit');

  -- Archiving is idempotent: only an actual transition is written and audited.
  if p_kind = 'audience' then
    update public.audiences set status = 'archived' where id = p_id and status = 'active';
  elsif p_kind = 'offer' then
    update public.offers set status = 'archived' where id = p_id and status = 'active';
  else
    update public.regions set status = 'archived' where id = p_id and status = 'active';
  end if;
  if not found then
    return;
  end if;

  perform app.audit(v_workspace_id, v_client_id, p_kind || '.archived', p_kind, p_id, null,
                    jsonb_build_object('status', 'archived'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Database API: sources and knowledge (knowledge.propose / knowledge.approve)
-- -----------------------------------------------------------------------------
create function public.create_source(
  p_client_id uuid,
  p_type public.source_type,
  p_title text,
  p_trust_level public.source_trust,
  p_uri text default null,
  p_occurred_at timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'knowledge.propose');
  v_title text := app.require_text(p_title, 'title');
  v_id uuid;
begin
  if p_type is null or p_trust_level is null then
    raise exception 'type and trust level are required' using errcode = '22023';
  end if;
  if p_trust_level = 'SYSTEM' then
    raise exception 'SYSTEM trust is reserved' using errcode = '22023';
  end if;

  insert into public.sources (client_id, type, title, trust_level, uri, occurred_at, created_by)
  values (p_client_id, p_type, v_title, p_trust_level, nullif(btrim(p_uri), ''), p_occurred_at,
          auth.uid())
  returning id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'source.created', 'source', v_id, null,
                    jsonb_build_object('trust_level', p_trust_level));
  return v_id;
end;
$$;

create function public.propose_fact(
  p_client_id uuid,
  p_source_id uuid,
  p_statement text,
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'knowledge.propose');
  v_id uuid;
begin
  perform app.client_source_trust(p_client_id, p_source_id);
  if p_valid_from is not null and p_valid_until is not null and p_valid_until <= p_valid_from then
    raise exception 'validity ends before it starts' using errcode = '22023';
  end if;

  insert into public.facts (client_id, source_id, statement, valid_from, valid_until, proposed_by)
  values (p_client_id, p_source_id, app.require_text(p_statement, 'statement'), p_valid_from,
          p_valid_until, auth.uid())
  returning id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'fact.proposed', 'fact', v_id, null, null);
  return v_id;
end;
$$;

create function public.propose_decision(
  p_client_id uuid,
  p_source_id uuid,
  p_statement text,
  p_rationale text default null,
  p_decided_at timestamptz default now()
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'knowledge.propose');
  v_id uuid;
begin
  perform app.client_source_trust(p_client_id, p_source_id);

  insert into public.decisions (client_id, source_id, statement, rationale, decided_at, owner_id)
  values (p_client_id, p_source_id, app.require_text(p_statement, 'statement'),
          nullif(btrim(p_rationale), ''), coalesce(p_decided_at, now()), auth.uid())
  returning id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'decision.proposed', 'decision', v_id, null, null);
  return v_id;
end;
$$;

create function public.propose_insight(
  p_client_id uuid,
  p_source_id uuid,
  p_statement text,
  p_confidence numeric default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'knowledge.propose');
  v_id uuid;
begin
  perform app.client_source_trust(p_client_id, p_source_id);
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then
    raise exception 'confidence must be between 0 and 1' using errcode = '22023';
  end if;

  insert into public.insights (client_id, source_id, statement, confidence, proposed_by)
  values (p_client_id, p_source_id, app.require_text(p_statement, 'statement'), p_confidence,
          auth.uid())
  returning id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'insight.proposed', 'insight', v_id, null, null);
  return v_id;
end;
$$;

-- Shared review step for proposed knowledge.
create function app.review_knowledge(
  p_kind public.knowledge_kind,
  p_id uuid,
  p_next public.knowledge_status
)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_client_id uuid;
  v_source_id uuid;
  v_status public.knowledge_status;
  v_workspace_id uuid;
begin
  if p_kind = 'fact' then
    select k.client_id, k.source_id, k.status into v_client_id, v_source_id, v_status
      from public.facts k where k.id = p_id;
  elsif p_kind = 'decision' then
    select k.client_id, k.source_id, k.status into v_client_id, v_source_id, v_status
      from public.decisions k where k.id = p_id;
  elsif p_kind = 'insight' then
    select k.client_id, k.source_id, k.status into v_client_id, v_source_id, v_status
      from public.insights k where k.id = p_id;
  end if;
  v_workspace_id := app.require_item_capability(v_client_id, 'knowledge.approve');

  -- Lock the item and re-read its state under the lock.
  if p_kind = 'fact' then
    select k.status into v_status from public.facts k where k.id = p_id for update;
  elsif p_kind = 'decision' then
    select k.status into v_status from public.decisions k where k.id = p_id for update;
  else
    select k.status into v_status from public.insights k where k.id = p_id for update;
  end if;
  if v_status <> 'proposed' then
    raise exception 'only proposed knowledge can be reviewed' using errcode = '22023';
  end if;
  if p_next = 'active' and p_kind in ('fact', 'decision')
     and app.client_source_trust(v_client_id, v_source_id) = 'UNTRUSTED_EXTERNAL' then
    raise exception 'untrusted sources cannot become facts or decisions' using errcode = '22023';
  end if;

  if p_kind = 'fact' then
    update public.facts
       set status = p_next, approved_by = case when p_next = 'active' then v_uid end
     where id = p_id;
  elsif p_kind = 'decision' then
    update public.decisions
       set status = p_next, approved_by = case when p_next = 'active' then v_uid end
     where id = p_id;
  else
    update public.insights
       set status = p_next, approved_by = case when p_next = 'active' then v_uid end
     where id = p_id;
  end if;

  perform app.audit(v_workspace_id, v_client_id,
                    p_kind::text || case p_next when 'active' then '.approved' else '.rejected' end,
                    p_kind::text, p_id,
                    jsonb_build_object('status', v_status), jsonb_build_object('status', p_next));
end;
$$;

create function public.approve_knowledge(p_kind public.knowledge_kind, p_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  select app.review_knowledge(p_kind, p_id, 'active');
$$;

create function public.reject_knowledge(p_kind public.knowledge_kind, p_id uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  select app.review_knowledge(p_kind, p_id, 'rejected');
$$;

-- -----------------------------------------------------------------------------
-- Database API: rules (knowledge.propose / rule.activate)
-- -----------------------------------------------------------------------------
create function public.propose_rule(
  p_client_id uuid,
  p_source_id uuid,
  p_type public.rule_type,
  p_subject text,
  p_statement text,
  p_channel text default null,
  p_priority integer default 50,
  p_effective_from timestamptz default null,
  p_effective_until timestamptz default null,
  p_supersedes_rule_id uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := app.require_client_capability(p_client_id, 'knowledge.propose');
  v_subject text := nullif(lower(btrim(p_subject)), '');
  v_channel text := nullif(lower(btrim(p_channel)), '');
  v_id uuid;
begin
  perform app.client_source_trust(p_client_id, p_source_id);
  if p_type is null then
    raise exception 'type is required' using errcode = '22023';
  end if;
  if p_type in ('MUST', 'MUST_NOT') and v_subject is null then
    raise exception 'hard rules require a subject' using errcode = '22023';
  end if;
  if v_channel is not null and v_channel !~ '^[a-z0-9][a-z0-9_-]{0,39}$' then
    raise exception 'invalid channel' using errcode = '22023';
  end if;
  if coalesce(p_priority, 50) not between 0 and 100 then
    raise exception 'priority must be between 0 and 100' using errcode = '22023';
  end if;
  if p_effective_from is not null and p_effective_until is not null
     and p_effective_until <= p_effective_from then
    raise exception 'validity ends before it starts' using errcode = '22023';
  end if;
  if p_supersedes_rule_id is not null and not exists (
    select 1 from public.rules r where r.id = p_supersedes_rule_id and r.client_id = p_client_id
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;

  insert into public.rules (
    client_id, source_id, type, subject, statement, scope_type, channel, priority,
    effective_from, effective_until, supersedes_rule_id, proposed_by
  )
  values (
    p_client_id, p_source_id, p_type, v_subject, app.require_text(p_statement, 'statement'),
    case when v_channel is null then 'client' else 'channel' end::public.rule_scope, v_channel,
    coalesce(p_priority, 50), p_effective_from, p_effective_until, p_supersedes_rule_id, auth.uid()
  )
  returning id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'rule.proposed', 'rule', v_id, null, null);
  return v_id;
end;
$$;

create function public.activate_rule(p_rule_id uuid)
returns public.rule_status
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_rule public.rules;
  v_old public.rules;
  v_workspace_id uuid;
  v_status public.rule_status;
begin
  select * into v_rule from public.rules r where r.id = p_rule_id;
  v_workspace_id := app.require_item_capability(v_rule.client_id, 'rule.activate');

  -- Serialize rule changes per client so conflict detection sees every concurrent activation.
  perform pg_advisory_xact_lock(hashtextextended('rules:' || v_rule.client_id::text, 0));
  select * into v_rule from public.rules r where r.id = p_rule_id for update;

  if v_rule.status <> 'proposed' then
    raise exception 'only proposed rules can be activated' using errcode = '22023';
  end if;
  if app.client_source_trust(v_rule.client_id, v_rule.source_id) = 'UNTRUSTED_EXTERNAL' then
    raise exception 'untrusted sources cannot become rules' using errcode = '22023';
  end if;
  if v_rule.effective_until is not null and v_rule.effective_until <= now() then
    raise exception 'rule validity has already ended' using errcode = '22023';
  end if;

  if v_rule.supersedes_rule_id is not null then
    select * into v_old from public.rules r
     where r.id = v_rule.supersedes_rule_id and r.client_id = v_rule.client_id
       for update;
    if v_old.status not in ('active', 'conflict') then
      raise exception 'only active or conflicting rules can be superseded' using errcode = '22023';
    end if;
    update public.rules set status = 'superseded' where id = v_old.id;
    perform app.audit(v_workspace_id, v_rule.client_id, 'rule.superseded', 'rule', v_old.id,
                      jsonb_build_object('status', v_old.status),
                      jsonb_build_object('status', 'superseded', 'superseded_by', v_rule.id));
  end if;

  update public.rules
     set status = 'active', approved_by = v_uid, activated_at = now()
   where id = v_rule.id;
  perform app.audit(v_workspace_id, v_rule.client_id, 'rule.activated', 'rule', v_rule.id,
                    jsonb_build_object('status', 'proposed'),
                    jsonb_build_object('status', 'active'));

  if v_rule.type in ('MUST', 'MUST_NOT') then
    perform app.recompute_rule_conflicts(v_workspace_id, v_rule.client_id, v_rule.subject);
  end if;
  -- The superseded rule may have been one side of a conflict: always release its old subject,
  -- whatever the type or subject of the superseding rule.
  if v_old.id is not null then
    perform app.recompute_rule_conflicts(v_workspace_id, v_rule.client_id, v_old.subject);
  end if;

  select r.status into v_status from public.rules r where r.id = v_rule.id;
  return v_status;
end;
$$;

create function public.reject_rule(p_rule_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rule public.rules;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_rule from public.rules r where r.id = p_rule_id;
  v_workspace_id := app.require_item_capability(v_rule.client_id, 'rule.activate');

  perform pg_advisory_xact_lock(hashtextextended('rules:' || v_rule.client_id::text, 0));
  select * into v_rule from public.rules r where r.id = p_rule_id for update;
  if v_rule.status not in ('proposed', 'conflict') then
    raise exception 'only proposed or conflicting rules can be rejected' using errcode = '22023';
  end if;

  update public.rules set status = 'rejected' where id = v_rule.id;
  perform app.audit(v_workspace_id, v_rule.client_id, 'rule.rejected', 'rule', v_rule.id,
                    jsonb_build_object('status', v_rule.status),
                    jsonb_build_object('status', 'rejected'));

  if v_rule.status = 'conflict' then
    perform app.recompute_rule_conflicts(v_workspace_id, v_rule.client_id, v_rule.subject);
  end if;
end;
$$;

-- Effective rules for a client (optionally a channel) at a point in time (docs/02 §4).
-- Rules valid at p_at and in scope are resolved per subject, with hard (MUST/MUST_NOT) and soft
-- (PREFER/AVOID) rules resolved separately so a preference never shadows an obligation:
--   * the narrower scope wins (channel over client), then the higher priority;
--   * rules in `conflict` take part in the ranking and are then dropped, so a conflict at the
--     winning level leaves the subject without an effective hard rule: nothing falls through to
--     a lower level (no automatic winner). Every hard rule valid at that level and moment is in
--     the conflict, because they all overlap at p_at;
--   * rules without a subject never shadow anything.
create function public.effective_rules(
  p_client_id uuid,
  p_channel text default null,
  p_at timestamptz default now()
)
returns table (
  id uuid,
  type public.rule_type,
  subject text,
  statement text,
  scope_type public.rule_scope,
  channel text,
  priority integer,
  effective_from timestamptz,
  effective_until timestamptz,
  source_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with candidates as (
    select r.*, (r.type in ('MUST', 'MUST_NOT')) as hard
      from public.rules r
     where r.client_id = p_client_id
       and app.has_internal_client_access(p_client_id)
       and r.status in ('active', 'conflict')
       and tstzrange(r.effective_from, r.effective_until, '[)') @> coalesce(p_at, now())
       and (r.scope_type = 'client'
            or (r.scope_type = 'channel' and r.channel = nullif(lower(btrim(p_channel)), '')))
  ),
  ranked as (
    select c.*,
           rank() over (partition by c.hard, coalesce(c.subject, c.id::text)
                        order by (c.scope_type = 'channel') desc, c.priority desc) as rk
      from candidates c
  )
  select k.id, k.type, k.subject, k.statement, k.scope_type, k.channel, k.priority,
         k.effective_from, k.effective_until, k.source_id
    from ranked k
   where k.rk = 1
     and k.status = 'active'
   order by k.subject nulls last, k.priority desc;
$$;

create function public.rule_conflicts(p_client_id uuid)
returns table (
  id uuid,
  type public.rule_type,
  subject text,
  statement text,
  scope_type public.rule_scope,
  channel text,
  priority integer,
  effective_from timestamptz,
  effective_until timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.type, r.subject, r.statement, r.scope_type, r.channel, r.priority,
         r.effective_from, r.effective_until
    from public.rules r
   where r.client_id = p_client_id
     and app.has_internal_client_access(p_client_id)
     and r.status = 'conflict'
   order by r.subject, r.priority desc;
$$;

-- -----------------------------------------------------------------------------
-- Row Level Security: internal staff with access to the client read; nobody writes directly.
-- -----------------------------------------------------------------------------
alter table public.brand_profiles enable row level security;
alter table public.audiences enable row level security;
alter table public.offers enable row level security;
alter table public.regions enable row level security;
alter table public.sources enable row level security;
alter table public.facts enable row level security;
alter table public.decisions enable row level security;
alter table public.insights enable row level security;
alter table public.rules enable row level security;

create policy brand_profiles_select_internal on public.brand_profiles
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy audiences_select_internal on public.audiences
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy offers_select_internal on public.offers
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy regions_select_internal on public.regions
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy sources_select_internal on public.sources
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy facts_select_internal on public.facts
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy decisions_select_internal on public.decisions
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy insights_select_internal on public.insights
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy rules_select_internal on public.rules
  for select to authenticated using (app.has_internal_client_access(client_id));

revoke all on table
  public.brand_profiles, public.audiences, public.offers, public.regions, public.sources,
  public.facts, public.decisions, public.insights, public.rules
from anon, authenticated;

grant select on table
  public.brand_profiles, public.audiences, public.offers, public.regions, public.sources,
  public.facts, public.decisions, public.insights, public.rules
to authenticated;

-- -----------------------------------------------------------------------------
-- Function privileges
-- -----------------------------------------------------------------------------
revoke execute on function
  app.require_client_capability(uuid, public.capability),
  app.require_item_capability(uuid, public.capability),
  app.require_text(text, text),
  app.client_source_trust(uuid, uuid),
  app.recompute_rule_conflicts(uuid, uuid, text),
  app.review_knowledge(public.knowledge_kind, uuid, public.knowledge_status)
from public, anon, authenticated;

revoke execute on function
  public.save_brand_profile(uuid, text, text, text, text[]),
  public.save_audience(uuid, uuid, text, text),
  public.save_offer(uuid, uuid, text, text, date, date),
  public.save_region(uuid, uuid, text, text),
  public.archive_context_item(text, uuid),
  public.create_source(uuid, public.source_type, text, public.source_trust, text, timestamptz),
  public.propose_fact(uuid, uuid, text, timestamptz, timestamptz),
  public.propose_decision(uuid, uuid, text, text, timestamptz),
  public.propose_insight(uuid, uuid, text, numeric),
  public.approve_knowledge(public.knowledge_kind, uuid),
  public.reject_knowledge(public.knowledge_kind, uuid),
  public.propose_rule(uuid, uuid, public.rule_type, text, text, text, integer, timestamptz,
                      timestamptz, uuid),
  public.activate_rule(uuid),
  public.reject_rule(uuid),
  public.effective_rules(uuid, text, timestamptz),
  public.rule_conflicts(uuid)
from public, anon;

grant execute on function
  public.save_brand_profile(uuid, text, text, text, text[]),
  public.save_audience(uuid, uuid, text, text),
  public.save_offer(uuid, uuid, text, text, date, date),
  public.save_region(uuid, uuid, text, text),
  public.archive_context_item(text, uuid),
  public.create_source(uuid, public.source_type, text, public.source_trust, text, timestamptz),
  public.propose_fact(uuid, uuid, text, timestamptz, timestamptz),
  public.propose_decision(uuid, uuid, text, text, timestamptz),
  public.propose_insight(uuid, uuid, text, numeric),
  public.approve_knowledge(public.knowledge_kind, uuid),
  public.reject_knowledge(public.knowledge_kind, uuid),
  public.propose_rule(uuid, uuid, public.rule_type, text, text, text, integer, timestamptz,
                      timestamptz, uuid),
  public.activate_rule(uuid),
  public.reject_rule(uuid),
  public.effective_rules(uuid, text, timestamptz),
  public.rule_conflicts(uuid)
to authenticated;
