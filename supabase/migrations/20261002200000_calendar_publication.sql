-- Increment 7 — Calendar + publication (docs/13): the publication schedule and a typed calendar
-- projection for internal staff and the client portal.
--
-- * A Publication distributes the client-approved revision of a content to a channel on a date
--   (docs/02, docs/04). It pins that exact revision and never modifies it to record delivery.
-- * v0.1 has no production social publishing (docs/13): "published" is recorded by a person.
-- * The calendar is a projection of typed dated events (docs/06). Each event names the one date
--   field a move changes: moving a publication never moves the production deadline
--   (docs/11 invariant 7), and vice versa.
-- * Clients see only their publications and open approval deadlines (docs/11 invariant 9).
-- Contract: tests/acceptance/increment-7/README.md.

create type public.publication_status as enum (
  'draft', 'scheduled', 'publishing', 'published', 'failed', 'retrying', 'canceled'
);

alter table public.contents add column production_due_at timestamptz;

create table public.publications (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  content_id uuid not null,
  revision_id uuid not null,
  channel text not null check (channel ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  scheduled_at timestamptz,
  published_at timestamptz,
  remote_id text check (char_length(remote_id) <= 200),
  remote_url text check (remote_url ~ '^https?://[^[:space:]]+$' and char_length(remote_url) <= 2000),
  status public.publication_status not null default 'draft',
  created_by uuid not null references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (content_id, client_id) references public.contents (id, client_id),
  foreign key (revision_id, content_id) references public.content_revisions (id, content_id),
  check (status <> 'scheduled' or scheduled_at is not null),
  check (status <> 'published' or published_at is not null)
);
create index publications_client_schedule_idx on public.publications (client_id, scheduled_at);
create index publications_content_idx on public.publications (content_id);
create index contents_production_due_idx on public.contents (client_id, production_due_at)
  where production_due_at is not null;

-- -----------------------------------------------------------------------------
-- Publication API
-- -----------------------------------------------------------------------------
create function public.schedule_publication(
  p_content_id uuid,
  p_scheduled_at timestamptz,
  p_channel text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_content public.contents;
  v_workspace_id uuid;
  v_channel text;
  v_id uuid;
begin
  select * into v_content from public.contents c where c.id = p_content_id;
  v_workspace_id := app.require_item_capability(v_content.client_id, 'publication.schedule');
  select * into v_content from public.contents c where c.id = p_content_id for update;
  -- Only what the client approved is distributed, and only while it is still the approved one.
  if v_content.status not in ('approved', 'scheduled', 'published')
     or v_content.client_approved_revision_id is null
     or v_content.client_approved_revision_id is distinct from v_content.approved_revision_id then
    raise exception 'only a client-approved revision can be scheduled' using errcode = '22023';
  end if;
  if p_scheduled_at is null or p_scheduled_at <= now() then
    raise exception 'publication date must be in the future' using errcode = '22023';
  end if;
  v_channel := coalesce(p_channel, v_content.channel);
  if v_channel !~ '^[a-z0-9][a-z0-9_-]{0,39}$' then
    raise exception 'invalid channel' using errcode = '22023';
  end if;

  insert into public.publications (client_id, content_id, revision_id, channel, scheduled_at,
                                   status, created_by)
  values (v_content.client_id, v_content.id, v_content.client_approved_revision_id, v_channel,
          p_scheduled_at, 'scheduled', v_uid)
  returning id into v_id;
  if v_content.status = 'approved' then
    update public.contents set status = 'scheduled' where id = v_content.id;
  end if;
  perform app.audit(v_workspace_id, v_content.client_id, 'publication.scheduled', 'publication',
                    v_id, null,
                    jsonb_build_object('content_id', v_content.id, 'channel', v_channel,
                                       'scheduled_at', p_scheduled_at));
  return v_id;
end;
$$;

create function public.reschedule_publication(p_publication_id uuid, p_scheduled_at timestamptz)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_publication public.publications;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_publication from public.publications p where p.id = p_publication_id;
  v_workspace_id := app.require_item_capability(v_publication.client_id, 'publication.schedule');
  select * into v_publication from public.publications p where p.id = p_publication_id for update;
  if v_publication.status <> 'scheduled' then
    raise exception 'this publication can no longer be changed' using errcode = '22023';
  end if;
  if p_scheduled_at is null or p_scheduled_at <= now() then
    raise exception 'publication date must be in the future' using errcode = '22023';
  end if;
  -- Only the publication date moves (docs/11 invariant 7).
  update public.publications
     set scheduled_at = p_scheduled_at, updated_at = now()
   where id = p_publication_id;
  perform app.audit(v_workspace_id, v_publication.client_id, 'publication.rescheduled',
                    'publication', p_publication_id,
                    jsonb_build_object('scheduled_at', v_publication.scheduled_at),
                    jsonb_build_object('scheduled_at', p_scheduled_at));
end;
$$;

create function public.cancel_publication(p_publication_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_publication public.publications;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_publication from public.publications p where p.id = p_publication_id;
  v_workspace_id := app.require_item_capability(v_publication.client_id, 'publication.schedule');
  -- Lock order: content, then publication (as scheduling does).
  perform 1 from public.contents c where c.id = v_publication.content_id for update;
  select * into v_publication from public.publications p where p.id = p_publication_id for update;
  if v_publication.status <> 'scheduled' then
    raise exception 'this publication can no longer be changed' using errcode = '22023';
  end if;
  update public.publications set status = 'canceled', updated_at = now() where id = p_publication_id;
  update public.contents c set status = 'approved'
   where c.id = v_publication.content_id and c.status = 'scheduled'
     and not exists (select 1 from public.publications p
                      where p.content_id = c.id and p.status in ('scheduled', 'publishing'));
  perform app.audit(v_workspace_id, v_publication.client_id, 'publication.canceled', 'publication',
                    p_publication_id, jsonb_build_object('status', 'scheduled'),
                    jsonb_build_object('status', 'canceled'));
end;
$$;

-- v0.1 records a publication done by a person (no production social publishing, docs/13).
create function public.mark_publication_published(p_publication_id uuid, p_remote_url text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_publication public.publications;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_publication from public.publications p where p.id = p_publication_id;
  v_workspace_id := app.require_item_capability(v_publication.client_id, 'publication.publish');
  perform 1 from public.contents c where c.id = v_publication.content_id for update;
  select * into v_publication from public.publications p where p.id = p_publication_id for update;
  if v_publication.status not in ('scheduled', 'publishing') then
    raise exception 'this publication can no longer be changed' using errcode = '22023';
  end if;
  if p_remote_url is not null
     and (p_remote_url !~ '^https?://[^[:space:]]+$' or char_length(p_remote_url) > 2000) then
    raise exception 'invalid remote url' using errcode = '22023';
  end if;
  -- Delivery data lives on the publication; the approved revision is never touched (docs/04).
  update public.publications
     set status = 'published', published_at = now(), remote_url = p_remote_url, updated_at = now()
   where id = p_publication_id;
  update public.contents set status = 'published'
   where id = v_publication.content_id and status in ('approved', 'scheduled');
  perform app.audit(v_workspace_id, v_publication.client_id, 'publication.published', 'publication',
                    p_publication_id, jsonb_build_object('status', v_publication.status),
                    jsonb_build_object('status', 'published', 'remote_url', p_remote_url));
end;
$$;

create function public.set_production_deadline(p_content_id uuid, p_due_at timestamptz)
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
  if v_content.status in ('canceled', 'archived') then
    raise exception 'this content can no longer be edited' using errcode = '22023';
  end if;
  -- Only the production deadline moves (docs/11 invariant 7).
  update public.contents set production_due_at = p_due_at where id = p_content_id;
  perform app.audit(v_workspace_id, v_content.client_id, 'content.deadline_set', 'content',
                    p_content_id, jsonb_build_object('production_due_at', v_content.production_due_at),
                    jsonb_build_object('production_due_at', p_due_at));
end;
$$;

-- -----------------------------------------------------------------------------
-- Typed calendar projection (docs/06 "Calendar model")
-- -----------------------------------------------------------------------------
create function public.calendar_events(
  p_from timestamptz,
  p_to timestamptz,
  p_client_id uuid default null
)
returns table (
  event_type text,
  client_id uuid,
  entity_id uuid,
  content_id uuid,
  title text,
  starts_at timestamptz,
  status text,
  date_field text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app.require_uid();
  if p_client_id is not null
     and not (app.has_internal_client_access(p_client_id) or app.is_client_member(p_client_id)) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '100 days' then
    raise exception 'invalid calendar range' using errcode = '22023';
  end if;

  return query
  -- Only the caller's own workspaces and client memberships are considered, so the cost follows
  -- the caller's reach rather than the number of tenants.
  with candidates as (
    select c.id
      from public.clients c
     where (p_client_id is null or c.id = p_client_id)
       and (c.workspace_id in (select w.workspace_id from public.workspace_memberships w
                                where w.user_id = auth.uid() and w.status = 'active')
            or c.id in (select m.client_id from public.client_memberships m
                         where m.user_id = auth.uid() and m.status = 'active'))
  ),
  access as (
    select k.id, app.has_internal_client_access(k.id) as internal from candidates k
  ),
  scope as (
    select a.id, a.internal from access a
     where a.internal or app.is_client_member(a.id)
  )
  select e.event_type, e.client_id, e.entity_id, e.content_id, e.title, e.starts_at, e.status,
         e.date_field
    from (
      select 'publication'::text as event_type, p.client_id, p.id as entity_id,
             p.content_id, c.title, p.scheduled_at as starts_at, p.status::text as status,
             'scheduled_at'::text as date_field
        from public.publications p
        join scope s on s.id = p.client_id
        join public.contents c on c.id = p.content_id
       where p.scheduled_at >= p_from and p.scheduled_at < p_to
         and (p.status in ('scheduled', 'publishing', 'published')
              or (s.internal and p.status in ('failed', 'retrying')))
      union all
      select 'production_deadline', c.client_id, c.id, c.id, c.title, c.production_due_at,
             c.status::text, 'production_due_at'
        from public.contents c
        join scope s on s.id = c.client_id and s.internal
       where c.production_due_at >= p_from and c.production_due_at < p_to
         and c.status not in ('canceled', 'archived')
      union all
      select 'approval_deadline', a.client_id, a.id, a.content_id, c.title, a.due_at,
             a.status::text, 'due_at'
        from public.approval_requests a
        join scope s on s.id = a.client_id
        join public.contents c on c.id = a.content_id
       where a.status = 'requested' and a.due_at >= p_from and a.due_at < p_to
      union all
      select 'meeting', m.client_id, m.id, null::uuid, m.title, m.starts_at,
             m.processing_status::text, 'starts_at'
        from public.meetings m
        join scope s on s.id = m.client_id and s.internal
       where m.starts_at >= p_from and m.starts_at < p_to
    ) e
   order by e.starts_at, e.event_type;
end;
$$;

-- The unscheduled backlog: content whose latest approved revision the client approved and that has
-- no publication yet. Runs with the caller's rights (RLS: internal staff only).
create function public.unscheduled_contents(p_client_ids uuid[])
returns table (id uuid, client_id uuid, title text, channel text)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.client_id, c.title, c.channel
    from public.contents c
   where c.client_id = any (p_client_ids)
     and c.status = 'approved'
     and c.client_approved_revision_id is not null
     and c.client_approved_revision_id = c.approved_revision_id
   order by c.updated_at desc
   limit 100;
$$;

-- -----------------------------------------------------------------------------
-- RLS and privileges
-- -----------------------------------------------------------------------------
alter table public.publications enable row level security;

create policy publications_select on public.publications
  for select to authenticated
  using (app.has_internal_client_access(client_id)
         or (app.is_client_member(client_id)
             and status in ('scheduled', 'publishing', 'published')));

revoke all on table public.publications from anon, authenticated;
grant select on table public.publications to authenticated;

revoke execute on function
  public.schedule_publication(uuid, timestamptz, text),
  public.reschedule_publication(uuid, timestamptz),
  public.cancel_publication(uuid),
  public.mark_publication_published(uuid, text),
  public.set_production_deadline(uuid, timestamptz),
  public.calendar_events(timestamptz, timestamptz, uuid),
  public.unscheduled_contents(uuid[])
from public, anon;
grant execute on function
  public.schedule_publication(uuid, timestamptz, text),
  public.reschedule_publication(uuid, timestamptz),
  public.cancel_publication(uuid),
  public.mark_publication_published(uuid, text),
  public.set_production_deadline(uuid, timestamptz),
  public.calendar_events(timestamptz, timestamptz, uuid),
  public.unscheduled_contents(uuid[])
to authenticated;
