-- Increment 6 — Collaboration + portal (docs/13): client approval of an exact content revision,
-- comments/threads with internal and client visibility, and the portal read model.
--
-- * An approval request targets exactly one immutable revision (docs/04 ApprovalRequest).
-- * Only client-side members with approval.decide decide; the agency never approves on the
--   client's behalf.
-- * Changing the content while the client reviews cancels the open request (stale revision,
--   docs/07 §15); a later revision is never client-approved without a new request
--   (docs/11 invariant 2).
-- * Clients see only what was sent to them: requests, the exact revision under request and
--   client-visible comments. Working content and internal comments stay internal (invariant 9).
-- Contract: tests/acceptance/increment-6/README.md.

create type public.approval_status as enum (
  'requested', 'approved', 'changes_requested', 'canceled', 'expired'
);
create type public.comment_visibility as enum ('internal', 'client');

alter table public.contents
  add column client_approved_revision_id uuid references public.content_revisions (id);

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  content_id uuid not null,
  revision_id uuid not null references public.content_revisions (id),
  status public.approval_status not null default 'requested',
  requested_by uuid not null references public.users (id),
  requested_at timestamptz not null default now(),
  due_at timestamptz,
  decided_at timestamptz,
  foreign key (content_id, client_id) references public.contents (id, client_id)
);
-- At most one open request per content.
create unique index approval_requests_one_open on public.approval_requests (content_id)
  where status = 'requested';
create index approval_requests_client_idx on public.approval_requests (client_id, status);

create table public.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null unique references public.approval_requests (id),
  client_id uuid not null references public.clients (id),
  approver_user_id uuid not null references public.users (id),
  decision text not null check (decision in ('approve', 'changes')),
  comment text check (char_length(comment) <= 4000),
  decided_at timestamptz not null default now()
);

create table public.threads (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  target_type text not null check (target_type in ('content')),
  target_id uuid not null,
  visibility public.comment_visibility not null,
  created_at timestamptz not null default now(),
  unique (target_type, target_id, visibility)
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.threads (id),
  client_id uuid not null references public.clients (id),
  author_id uuid not null references public.users (id),
  -- Display name copied at write time: clients cannot read other people's profiles.
  author_name text not null default '' check (char_length(author_name) <= 200),
  body text not null check (btrim(body) <> '' and char_length(body) <= 4000),
  created_at timestamptz not null default now(),
  edited_at timestamptz
);
create index comments_thread_idx on public.comments (thread_id, created_at);

-- Decisions are immutable records.
create function app.approval_decisions_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'approval decisions are immutable' using errcode = '55000';
end;
$$;
create trigger approval_decisions_no_update_or_delete
  before update or delete on public.approval_decisions
  for each row execute function app.approval_decisions_immutable();

-- A content change while the client reviews makes the open request stale.
create function app.cancel_stale_approval_requests()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.working_payload is distinct from old.working_payload
     or (old.status = 'client_review' and new.status in ('producing', 'internal_review')) then
    update public.approval_requests
       set status = 'canceled', decided_at = now()
     where content_id = new.id and status = 'requested';
  end if;
  return new;
end;
$$;
create trigger contents_cancel_stale_requests
  after update on public.contents
  for each row execute function app.cancel_stale_approval_requests();

-- Editing is also allowed while the client reviews (it cancels the request, above).
create or replace function public.save_content_payload(p_content_id uuid, p_payload jsonb)
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
  if v_content.status not in ('ready', 'producing', 'internal_review', 'client_review', 'approved') then
    raise exception 'this content can no longer be edited' using errcode = '22023';
  end if;
  update public.contents c
     set working_payload = app.validate_content_payload(p_payload), status = 'producing'
   where c.id = p_content_id;
  perform app.audit(v_workspace_id, v_content.client_id, 'content.edited', 'content', p_content_id,
                    jsonb_build_object('status', v_content.status),
                    jsonb_build_object('status', 'producing'));
end;
$$;

-- Capabilities a client-side member holds on a client (internal grants never count here).
create function app.client_side_capabilities(p_user uuid, p_client_id uuid)
returns public.capability[]
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select app.normalize_capabilities(app.client_role_defaults(m.role) || m.capabilities)
       from public.client_memberships m
      where m.client_id = p_client_id and m.user_id = p_user and m.status = 'active'),
    '{}');
$$;

-- -----------------------------------------------------------------------------
-- Approval API
-- -----------------------------------------------------------------------------
create function public.request_client_approval(p_revision_id uuid, p_due_at timestamptz default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_client_id uuid;
  v_workspace_id uuid;
  v_content public.contents;
  v_id uuid;
begin
  perform app.require_uid();
  select r.client_id into v_client_id from public.content_revisions r where r.id = p_revision_id;
  v_workspace_id := app.require_item_capability(v_client_id, 'approval.request');
  select c.* into v_content
    from public.contents c join public.content_revisions r on r.content_id = c.id
   where r.id = p_revision_id
     for update of c;
  if v_content.status <> 'approved' or v_content.approved_revision_id is distinct from p_revision_id then
    raise exception 'only an internally approved revision can be sent to the client'
      using errcode = '22023';
  end if;
  if exists (select 1 from public.approval_requests a
              where a.content_id = v_content.id and a.status = 'requested') then
    raise exception 'this content already has an open approval request' using errcode = '22023';
  end if;

  insert into public.approval_requests (client_id, content_id, revision_id, requested_by, due_at)
  values (v_client_id, v_content.id, p_revision_id, auth.uid(), p_due_at)
  returning id into v_id;
  update public.contents set status = 'client_review' where id = v_content.id;
  perform app.audit(v_workspace_id, v_client_id, 'approval.requested', 'approval_request', v_id,
                    null, jsonb_build_object('revision_id', p_revision_id));
  return v_id;
end;
$$;

create function public.decide_approval(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_request public.approval_requests;
  v_content public.contents;
  v_workspace_id uuid;
begin
  select * into v_request from public.approval_requests a where a.id = p_request_id;
  if v_request.id is null
     or not (app.is_client_member(v_request.client_id)
             or app.has_internal_client_access(v_request.client_id)) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  -- Only the client decides: internal grants never count (docs/01, docs/05 §2).
  if not ('approval.decide' = any (app.client_side_capabilities(v_uid, v_request.client_id))) then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  if p_decision is null or p_decision not in ('approve', 'changes') then
    raise exception 'unknown approval decision' using errcode = '22023';
  end if;
  if char_length(p_comment) > 4000 then
    raise exception 'comment is too long' using errcode = '22023';
  end if;

  select * into v_request from public.approval_requests a where a.id = p_request_id for update;
  select * into v_content from public.contents c where c.id = v_request.content_id for update;
  if v_request.status <> 'requested' then
    raise exception 'this approval request is no longer open' using errcode = '22023';
  end if;
  if v_content.status <> 'client_review'
     or v_content.approved_revision_id is distinct from v_request.revision_id then
    raise exception 'this approval request is no longer open' using errcode = '22023';
  end if;

  update public.approval_requests
     set status = case p_decision when 'approve' then 'approved'::public.approval_status
                                  else 'changes_requested'::public.approval_status end,
         decided_at = now()
   where id = p_request_id;
  insert into public.approval_decisions (approval_request_id, client_id, approver_user_id, decision,
                                         comment)
  values (p_request_id, v_request.client_id, v_uid, p_decision, nullif(btrim(p_comment), ''));
  if p_decision = 'approve' then
    update public.contents
       set status = 'approved', client_approved_revision_id = v_request.revision_id
     where id = v_content.id;
  else
    update public.contents set status = 'producing' where id = v_content.id;
  end if;

  select c.workspace_id into v_workspace_id from public.clients c where c.id = v_request.client_id;
  perform app.audit(v_workspace_id, v_request.client_id,
                    case p_decision when 'approve' then 'approval.approved'
                                    else 'approval.changes_requested' end,
                    'approval_request', p_request_id, jsonb_build_object('status', 'requested'),
                    jsonb_build_object('decision', p_decision, 'revision_id', v_request.revision_id));
end;
$$;

create function public.cancel_approval_request(p_request_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_request public.approval_requests;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_request from public.approval_requests a where a.id = p_request_id;
  v_workspace_id := app.require_item_capability(v_request.client_id, 'approval.request');
  select * into v_request from public.approval_requests a where a.id = p_request_id for update;
  if v_request.status <> 'requested' then
    raise exception 'this approval request is no longer open' using errcode = '22023';
  end if;
  update public.approval_requests set status = 'canceled', decided_at = now() where id = p_request_id;
  update public.contents set status = 'approved'
   where id = v_request.content_id and status = 'client_review';
  perform app.audit(v_workspace_id, v_request.client_id, 'approval.canceled', 'approval_request',
                    p_request_id, jsonb_build_object('status', 'requested'),
                    jsonb_build_object('status', 'canceled'));
end;
$$;

-- Portal read model: the requests of a client with the exact revision under request.
create function public.portal_approvals(p_client_id uuid)
returns table (
  request_id uuid,
  status public.approval_status,
  content_title text,
  channel text,
  format text,
  revision_number integer,
  payload jsonb,
  requested_at timestamptz,
  due_at timestamptz,
  decided_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id, a.status, c.title, c.channel, c.format, r.revision_number, r.payload,
         a.requested_at, a.due_at, a.decided_at
    from public.approval_requests a
    join public.contents c on c.id = a.content_id
    join public.content_revisions r on r.id = a.revision_id
   where a.client_id = p_client_id
     and (app.is_client_member(p_client_id) or app.has_internal_client_access(p_client_id))
   order by a.requested_at desc;
$$;

-- -----------------------------------------------------------------------------
-- Comments
-- -----------------------------------------------------------------------------
create function public.add_comment(
  p_target_type text,
  p_target_id uuid,
  p_body text,
  p_visibility text default 'client'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app.require_uid();
  v_client_id uuid;
  v_visibility public.comment_visibility;
  v_internal boolean;
  v_thread_id uuid;
  v_id uuid;
begin
  if p_target_type is null or p_target_type <> 'content' then
    raise exception 'unknown comment target' using errcode = '22023';
  end if;
  select c.client_id into v_client_id from public.contents c where c.id = p_target_id;
  v_internal := v_client_id is not null and app.has_internal_client_access(v_client_id);
  if not v_internal and not (
    v_client_id is not null
    and app.is_client_member(v_client_id)
    -- Clients only reach content that was sent to them.
    and exists (select 1 from public.approval_requests a where a.content_id = p_target_id)
  ) then
    raise exception 'not found' using errcode = 'P0002';
  end if;
  if p_visibility is null or p_visibility not in ('internal', 'client') then
    raise exception 'unknown comment visibility' using errcode = '22023';
  end if;
  v_visibility := p_visibility::public.comment_visibility;
  if not v_internal then
    -- Client-side: client-visible comments only, and never by read-only viewers.
    if v_visibility = 'internal'
       or not (app.client_side_capabilities(v_uid, v_client_id)
               && array['approval.decide', 'request.submit']::public.capability[]) then
      raise exception 'permission denied' using errcode = '42501';
    end if;
  end if;
  if p_body is null or btrim(p_body) = '' or char_length(p_body) > 4000 then
    raise exception 'comment is required' using errcode = '22023';
  end if;

  insert into public.threads (client_id, target_type, target_id, visibility)
  values (v_client_id, p_target_type, p_target_id, v_visibility)
  on conflict (target_type, target_id, visibility) do nothing;
  select t.id into v_thread_id from public.threads t
   where t.target_type = p_target_type and t.target_id = p_target_id and t.visibility = v_visibility;

  insert into public.comments (thread_id, client_id, author_id, author_name, body)
  values (v_thread_id, v_client_id, v_uid,
          coalesce((select left(u.display_name, 200) from public.users u where u.id = v_uid), ''),
          btrim(p_body))
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS and privileges
-- -----------------------------------------------------------------------------
alter table public.approval_requests enable row level security;
alter table public.approval_decisions enable row level security;
alter table public.threads enable row level security;
alter table public.comments enable row level security;

create policy approval_requests_select on public.approval_requests
  for select to authenticated
  using (app.has_internal_client_access(client_id) or app.is_client_member(client_id));
create policy approval_decisions_select on public.approval_decisions
  for select to authenticated
  using (app.has_internal_client_access(client_id) or app.is_client_member(client_id));
create policy threads_select on public.threads
  for select to authenticated
  using (app.has_internal_client_access(client_id)
         or (visibility = 'client' and app.is_client_member(client_id)));
create policy comments_select on public.comments
  for select to authenticated
  using (app.has_internal_client_access(client_id)
         or (app.is_client_member(client_id)
             and exists (select 1 from public.threads t
                          where t.id = comments.thread_id and t.visibility = 'client')));
-- Clients see exactly the revisions that were sent to them.
create policy content_revisions_select_client on public.content_revisions
  for select to authenticated
  using (app.is_client_member(client_id)
         and exists (select 1 from public.approval_requests a
                      where a.revision_id = content_revisions.id));

revoke all on table public.approval_requests, public.approval_decisions, public.threads,
  public.comments from anon, authenticated;
grant select on table public.approval_requests, public.approval_decisions, public.threads,
  public.comments to authenticated;

revoke execute on function
  app.approval_decisions_immutable(),
  app.cancel_stale_approval_requests(),
  app.client_side_capabilities(uuid, uuid)
from public, anon, authenticated;

revoke execute on function
  public.request_client_approval(uuid, timestamptz),
  public.decide_approval(uuid, text, text),
  public.cancel_approval_request(uuid),
  public.portal_approvals(uuid),
  public.add_comment(text, uuid, text, text)
from public, anon;
grant execute on function
  public.request_client_approval(uuid, timestamptz),
  public.decide_approval(uuid, text, text),
  public.cancel_approval_request(uuid),
  public.portal_approvals(uuid),
  public.add_comment(text, uuid, text, text)
to authenticated;
