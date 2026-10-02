-- Increment 4 — Meeting intelligence (docs/13): Meeting with its own Source, transcripts,
-- transcription and extraction jobs, and human review of extracted proposals.
--
-- * Meetings, transcripts and proposals are internal-only (RLS) and never written directly.
-- * Every meeting owns a FIRST_PARTY `meeting` Source: provenance for whatever it yields.
-- * The worker reads meeting content and writes results only through `worker.*` functions
--   scoped to its leased job and fenced by (lease_owner, attempt). Domain rows are written in the
--   same transaction as the job completion, so a duplicate delivery writes nothing (docs/11 #6).
-- * Model output only ever becomes `meeting_proposals`. A person accepts a proposal into the
--   Client Brain as PROPOSED knowledge (Increment 2 decision 2); approval/activation remain
--   separate capability-checked steps (docs/11 #4, #5).
-- Contract: tests/acceptance/increment-4/README.md.

create type public.meeting_status as enum (
  'new', 'transcribing', 'transcribed', 'extracting', 'in_review'
);
create type public.transcript_origin as enum ('manual', 'transcription');
create type public.proposal_kind as enum ('fact', 'decision', 'rule', 'insight', 'task');
create type public.proposal_status as enum ('proposed', 'accepted', 'rejected');

-- Relative path under the worker's media root: segments must start with a letter or digit, so
-- `..`, absolute paths and hidden files are impossible.
create function app.is_recording_ref(p_ref text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_ref is null
      or (char_length(p_ref) <= 500
          and p_ref ~ '^[A-Za-z0-9][A-Za-z0-9._ -]*(/[A-Za-z0-9][A-Za-z0-9._ -]*)*$');
$$;

create table public.meetings (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id),
  title text not null check (btrim(title) <> '' and char_length(title) <= 300),
  starts_at timestamptz not null,
  ends_at timestamptz check (ends_at is null or ends_at >= starts_at),
  participants jsonb not null default '[]'::jsonb
    check (jsonb_typeof(participants) = 'array' and jsonb_array_length(participants) <= 50
           and octet_length(participants::text) <= 20000),
  recording_ref text check (app.is_recording_ref(recording_ref)),
  transcript_source_id uuid not null,
  processing_status public.meeting_status not null default 'new',
  owner_id uuid references public.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, client_id),
  foreign key (transcript_source_id, client_id) references public.sources (id, client_id)
);
create index meetings_client_idx on public.meetings (client_id, starts_at desc);

create table public.meeting_transcripts (
  meeting_id uuid not null references public.meetings (id),
  revision integer not null check (revision >= 1),
  text text not null check (btrim(text) <> '' and char_length(text) <= 500000),
  segments jsonb not null default '[]'::jsonb
    check (jsonb_typeof(segments) = 'array' and octet_length(segments::text) <= 4000000),
  language text check (char_length(language) <= 20),
  origin public.transcript_origin not null,
  job_id uuid references public.jobs (id),
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  primary key (meeting_id, revision)
);

create table public.meeting_proposals (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null,
  client_id uuid not null,
  job_id uuid not null references public.jobs (id),
  transcript_revision integer not null,
  kind public.proposal_kind not null,
  statement text not null check (btrim(statement) <> '' and char_length(statement) <= 2000),
  rule_type public.rule_type,
  subject text check (subject is null or (subject = lower(btrim(subject)) and subject <> ''
                                          and char_length(subject) <= 80)),
  confidence numeric(3, 2) check (confidence between 0 and 1),
  evidence_quote text check (char_length(evidence_quote) <= 1000),
  time_ref text check (char_length(time_ref) <= 50),
  status public.proposal_status not null default 'proposed',
  accepted_item_id uuid,
  reviewed_by uuid references public.users (id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (meeting_id, client_id) references public.meetings (id, client_id),
  check ((kind = 'rule') = (rule_type is not null)),
  check ((status = 'accepted') = (accepted_item_id is not null))
);
create index meeting_proposals_meeting_idx on public.meeting_proposals (meeting_id, status);

create trigger meetings_updated_at before update on public.meetings
  for each row execute function app.set_updated_at();

-- -----------------------------------------------------------------------------
-- Database API (knowledge.propose)
-- -----------------------------------------------------------------------------
create function public.create_meeting(
  p_client_id uuid,
  p_title text,
  p_starts_at timestamptz,
  p_ends_at timestamptz default null,
  p_participants jsonb default '[]'::jsonb,
  p_recording_ref text default null
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
  v_ref text := nullif(btrim(p_recording_ref), '');
  v_participants jsonb := coalesce(p_participants, '[]'::jsonb);
  v_source_id uuid;
  v_id uuid;
begin
  if p_starts_at is null then
    raise exception 'starts_at is required' using errcode = '22023';
  end if;
  if p_ends_at is not null and p_ends_at < p_starts_at then
    raise exception 'a meeting cannot end before it starts' using errcode = '22023';
  end if;
  if char_length(v_title) > 300 then
    raise exception 'title is too long' using errcode = '22023';
  end if;
  if not app.is_recording_ref(v_ref) then
    raise exception 'invalid recording reference' using errcode = '22023';
  end if;
  if jsonb_typeof(v_participants) <> 'array' or jsonb_array_length(v_participants) > 50
     or exists (
       select 1 from jsonb_array_elements(v_participants) p
        where jsonb_typeof(p) <> 'object'
           or jsonb_typeof(p -> 'name') is distinct from 'string'
           or btrim(p ->> 'name') = '' or char_length(p ->> 'name') > 200
     ) then
    raise exception 'invalid participants' using errcode = '22023';
  end if;

  insert into public.sources (client_id, type, title, trust_level, created_by, occurred_at)
  values (p_client_id, 'meeting', left('Reunião: ' || v_title, 300), 'FIRST_PARTY', auth.uid(),
          p_starts_at)
  returning id into v_source_id;

  insert into public.meetings (
    client_id, title, starts_at, ends_at, participants, recording_ref, transcript_source_id,
    owner_id
  )
  values (p_client_id, v_title, p_starts_at, p_ends_at, v_participants, v_ref, v_source_id,
          auth.uid())
  returning id into v_id;

  perform app.audit(v_workspace_id, p_client_id, 'meeting.created', 'meeting', v_id, null, null);
  return v_id;
end;
$$;

-- Locks a meeting the caller may work on (P0002 not visible, 42501 without knowledge.propose).
create function app.require_meeting(p_meeting_id uuid, out meeting public.meetings,
                                    out workspace_id uuid)
language plpgsql
volatile
set search_path = ''
as $$
begin
  select * into meeting from public.meetings m where m.id = p_meeting_id;
  workspace_id := app.require_item_capability(meeting.client_id, 'knowledge.propose');
  select * into meeting from public.meetings m where m.id = p_meeting_id for update;
end;
$$;

create function public.save_meeting_transcript(p_meeting_id uuid, p_text text)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope record := app.require_meeting(p_meeting_id);
  v_text text := app.require_text(p_text, 'transcript');
  v_revision integer;
begin
  if char_length(v_text) > 500000 then
    raise exception 'transcript is too long' using errcode = '22023';
  end if;
  select coalesce(max(t.revision), 0) + 1 into v_revision
    from public.meeting_transcripts t where t.meeting_id = p_meeting_id;

  insert into public.meeting_transcripts (meeting_id, revision, text, origin, created_by)
  values (p_meeting_id, v_revision, v_text, 'manual', auth.uid());
  update public.meetings set processing_status = 'transcribed' where id = p_meeting_id;

  perform app.audit(v_scope.workspace_id, (v_scope.meeting).client_id, 'meeting.transcript_saved',
                    'meeting', p_meeting_id, null, jsonb_build_object('revision', v_revision));
  return v_revision;
end;
$$;

create function public.request_meeting_extraction(p_meeting_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope record := app.require_meeting(p_meeting_id);
  v_meeting public.meetings := v_scope.meeting;
  v_revision integer;
  v_key text;
  v_existed boolean;
  v_job_id uuid;
begin
  select max(t.revision) into v_revision
    from public.meeting_transcripts t where t.meeting_id = p_meeting_id;
  if v_revision is null then
    raise exception 'meeting has no transcript' using errcode = '22023';
  end if;

  -- One extraction per transcript revision (docs/11 invariant 6).
  v_key := 'meeting.extract.v1:' || p_meeting_id::text || ':' || v_revision::text;
  select exists (
    select 1 from public.jobs j
     where j.workspace_id = v_scope.workspace_id and j.idempotency_key = v_key
  ) into v_existed;
  v_job_id := app.enqueue_job(
    v_scope.workspace_id, v_meeting.client_id, 'meeting.extract', 1, v_key,
    jsonb_build_object('meeting_id', p_meeting_id, 'transcript_revision', v_revision),
    50, 3, 'reasoning', 'meeting.extract/1', null, auth.uid()
  );
  if not v_existed then
    update public.meetings set processing_status = 'extracting' where id = p_meeting_id;
    perform app.audit(v_scope.workspace_id, v_meeting.client_id, 'meeting.extraction_requested',
                      'meeting', p_meeting_id, null,
                      jsonb_build_object('job_id', v_job_id, 'revision', v_revision));
  end if;
  return v_job_id;
end;
$$;

create function public.request_meeting_transcription(p_meeting_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_scope record := app.require_meeting(p_meeting_id);
  v_meeting public.meetings := v_scope.meeting;
  v_key text;
  v_existed boolean;
  v_job_id uuid;
begin
  if v_meeting.recording_ref is null then
    raise exception 'meeting has no recording reference' using errcode = '22023';
  end if;

  v_key := 'meeting.transcribe.v1:' || p_meeting_id::text || ':' || md5(v_meeting.recording_ref);
  select exists (
    select 1 from public.jobs j
     where j.workspace_id = v_scope.workspace_id and j.idempotency_key = v_key
  ) into v_existed;
  v_job_id := app.enqueue_job(
    v_scope.workspace_id, v_meeting.client_id, 'meeting.transcribe', 1, v_key,
    jsonb_build_object('meeting_id', p_meeting_id), 50, 3, 'transcription',
    'meeting.transcribe/1', null, auth.uid()
  );
  if not v_existed then
    update public.meetings set processing_status = 'transcribing' where id = p_meeting_id;
    perform app.audit(v_scope.workspace_id, v_meeting.client_id,
                      'meeting.transcription_requested', 'meeting', p_meeting_id, null,
                      jsonb_build_object('job_id', v_job_id));
  end if;
  return v_job_id;
end;
$$;

-- Accepting creates PROPOSED knowledge through the Increment 2 API (same checks, same audit).
create function public.accept_meeting_proposal(p_proposal_id uuid, p_statement text default null)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_proposal public.meeting_proposals;
  v_workspace_id uuid;
  v_source_id uuid;
  v_statement text;
  v_item_id uuid;
begin
  perform app.require_uid();
  select * into v_proposal from public.meeting_proposals p where p.id = p_proposal_id;
  v_workspace_id := app.require_item_capability(v_proposal.client_id, 'knowledge.propose');
  select * into v_proposal from public.meeting_proposals p where p.id = p_proposal_id for update;

  if v_proposal.status <> 'proposed' then
    raise exception 'only proposed items can be reviewed' using errcode = '22023';
  end if;
  if v_proposal.kind = 'task' then
    raise exception 'tasks cannot be promoted yet' using errcode = '22023';
  end if;

  v_statement := coalesce(nullif(btrim(p_statement), ''), v_proposal.statement);
  select m.transcript_source_id into v_source_id
    from public.meetings m where m.id = v_proposal.meeting_id;

  v_item_id := case v_proposal.kind
    when 'fact' then public.propose_fact(v_proposal.client_id, v_source_id, v_statement)
    when 'decision' then public.propose_decision(v_proposal.client_id, v_source_id, v_statement)
    when 'insight' then public.propose_insight(v_proposal.client_id, v_source_id, v_statement,
                                               v_proposal.confidence)
    when 'rule' then public.propose_rule(v_proposal.client_id, v_source_id, v_proposal.rule_type,
                                         v_proposal.subject, v_statement)
  end;

  update public.meeting_proposals
     set status = 'accepted', accepted_item_id = v_item_id, reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_proposal_id;

  perform app.audit(v_workspace_id, v_proposal.client_id, 'meeting_proposal.accepted',
                    'meeting_proposal', p_proposal_id, jsonb_build_object('status', 'proposed'),
                    jsonb_build_object('status', 'accepted', 'kind', v_proposal.kind,
                                       'item_id', v_item_id,
                                       'edited', v_statement <> v_proposal.statement));
  return v_item_id;
end;
$$;

create function public.reject_meeting_proposal(p_proposal_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_proposal public.meeting_proposals;
  v_workspace_id uuid;
begin
  perform app.require_uid();
  select * into v_proposal from public.meeting_proposals p where p.id = p_proposal_id;
  v_workspace_id := app.require_item_capability(v_proposal.client_id, 'knowledge.propose');
  select * into v_proposal from public.meeting_proposals p where p.id = p_proposal_id for update;
  if v_proposal.status <> 'proposed' then
    raise exception 'only proposed items can be reviewed' using errcode = '22023';
  end if;

  update public.meeting_proposals
     set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_proposal_id;

  perform app.audit(v_workspace_id, v_proposal.client_id, 'meeting_proposal.rejected',
                    'meeting_proposal', p_proposal_id, jsonb_build_object('status', 'proposed'),
                    jsonb_build_object('status', 'rejected'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Worker API: meeting content and results, scoped to the leased job
-- -----------------------------------------------------------------------------
create function worker.meeting_for_job(p_job_id uuid, p_worker_id text, p_attempt integer)
returns table (
  meeting_id uuid,
  title text,
  recording_ref text,
  transcript text,
  transcript_revision integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform worker.assert_worker_id(p_worker_id);
  return query
  select m.id, m.title, m.recording_ref, t.text, t.revision
    from public.jobs j
    join public.meetings m
      on m.id = (j.input ->> 'meeting_id')::uuid and m.client_id = j.client_id
    left join public.meeting_transcripts t
      on t.meeting_id = m.id and t.revision = (j.input ->> 'transcript_revision')::integer
   where j.id = p_job_id
     and j.status = 'running'
     and j.lease_owner = p_worker_id
     and j.attempts = p_attempt
     and j.type in ('meeting.extract', 'meeting.transcribe')
     and j.schema_version = 1;
end;
$$;

-- Shared fencing for domain completions: 'ok' when the caller holds the lease of a job of the
-- expected type, otherwise 'duplicate' / 'lease_lost'. Locks the job row.
create function worker.lease_for_completion(
  p_job_id uuid, p_worker_id text, p_attempt integer, p_type text, out outcome text,
  out job public.jobs
)
language plpgsql
volatile
set search_path = ''
as $$
begin
  perform worker.assert_worker_id(p_worker_id);
  select * into job from public.jobs j where j.id = p_job_id for update;
  if job.id is null then
    raise exception 'job % not found', p_job_id using errcode = 'P0002';
  end if;
  if job.status = 'completed' then
    outcome := 'duplicate';
  elsif job.status <> 'running' or job.lease_owner is distinct from p_worker_id
        or job.attempts <> p_attempt then
    outcome := 'lease_lost';
  elsif job.type <> p_type or job.schema_version <> 1 then
    raise exception 'job % is not a % job', p_job_id, p_type using errcode = '22023';
  else
    outcome := 'ok';
  end if;
end;
$$;

create function worker.finish_job(p_job_id uuid, p_result jsonb)
returns void
language sql
volatile
set search_path = ''
as $$
  update public.jobs
     set status = 'completed', result = p_result, last_error = null, lease_owner = null,
         lease_until = null, finished_at = now()
   where id = p_job_id;
$$;

create function worker.complete_meeting_extraction(
  p_job_id uuid,
  p_worker_id text,
  p_attempt integer,
  p_result jsonb
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lease record := worker.lease_for_completion(p_job_id, p_worker_id, p_attempt,
                                                'meeting.extract');
  v_job public.jobs := v_lease.job;
  v_meeting_id uuid;
  v_revision integer;
  v_item jsonb;
  v_count integer := 0;
begin
  if v_lease.outcome <> 'ok' then
    return v_lease.outcome;
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or jsonb_typeof(p_result -> 'proposals') <> 'array'
     or jsonb_array_length(p_result -> 'proposals') > 100 then
    raise exception 'invalid extraction result' using errcode = '22023';
  end if;

  v_meeting_id := (v_job.input ->> 'meeting_id')::uuid;
  v_revision := (v_job.input ->> 'transcript_revision')::integer;

  for v_item in select value from jsonb_array_elements(p_result -> 'proposals') loop
    if jsonb_typeof(v_item) <> 'object'
       or v_item ->> 'kind' not in ('fact', 'decision', 'rule', 'insight', 'task')
       or jsonb_typeof(v_item -> 'statement') is distinct from 'string'
       or (v_item ? 'confidence' and jsonb_typeof(v_item -> 'confidence') <> 'number')
       or ((v_item ->> 'kind') = 'rule')
          <> (coalesce(v_item ->> 'rule_type', '') in ('MUST', 'MUST_NOT', 'PREFER', 'AVOID'))
    then
      raise exception 'invalid extraction result' using errcode = '22023';
    end if;

    insert into public.meeting_proposals (
      meeting_id, client_id, job_id, transcript_revision, kind, statement, rule_type, subject,
      confidence, evidence_quote, time_ref
    )
    values (
      v_meeting_id, v_job.client_id, v_job.id, v_revision,
      (v_item ->> 'kind')::public.proposal_kind,
      btrim(v_item ->> 'statement'),
      case when v_item ->> 'kind' = 'rule' then (v_item ->> 'rule_type')::public.rule_type end,
      case when v_item ->> 'kind' = 'rule'
           then nullif(lower(btrim(v_item ->> 'subject')), '') end,
      (v_item ->> 'confidence')::numeric,
      nullif(btrim(v_item ->> 'evidence_quote'), ''),
      nullif(btrim(v_item ->> 'time_ref'), '')
    );
    v_count := v_count + 1;
  end loop;

  update public.meetings set processing_status = 'in_review'
   where id = v_meeting_id and client_id = v_job.client_id;
  perform worker.finish_job(v_job.id, jsonb_build_object('proposals', v_count));
  return 'completed';
end;
$$;

create function worker.complete_meeting_transcription(
  p_job_id uuid,
  p_worker_id text,
  p_attempt integer,
  p_result jsonb
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lease record := worker.lease_for_completion(p_job_id, p_worker_id, p_attempt,
                                                'meeting.transcribe');
  v_job public.jobs := v_lease.job;
  v_meeting_id uuid;
  v_revision integer;
begin
  if v_lease.outcome <> 'ok' then
    return v_lease.outcome;
  end if;
  if p_result is null or jsonb_typeof(p_result) <> 'object'
     or jsonb_typeof(p_result -> 'text') is distinct from 'string'
     or btrim(p_result ->> 'text') = ''
     or jsonb_typeof(coalesce(p_result -> 'segments', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid transcription result' using errcode = '22023';
  end if;

  v_meeting_id := (v_job.input ->> 'meeting_id')::uuid;
  perform 1 from public.meetings m where m.id = v_meeting_id and m.client_id = v_job.client_id
    for update;
  select coalesce(max(t.revision), 0) + 1 into v_revision
    from public.meeting_transcripts t where t.meeting_id = v_meeting_id;

  insert into public.meeting_transcripts (meeting_id, revision, text, segments, language, origin,
                                          job_id)
  values (v_meeting_id, v_revision, p_result ->> 'text',
          coalesce(p_result -> 'segments', '[]'::jsonb), nullif(p_result ->> 'language', ''),
          'transcription', v_job.id);
  update public.meetings set processing_status = 'transcribed'
   where id = v_meeting_id and client_id = v_job.client_id;
  perform worker.finish_job(v_job.id, jsonb_build_object(
    'revision', v_revision, 'characters', char_length(p_result ->> 'text')));
  return 'completed';
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS and privileges
-- -----------------------------------------------------------------------------
alter table public.meetings enable row level security;
alter table public.meeting_transcripts enable row level security;
alter table public.meeting_proposals enable row level security;

create policy meetings_select_internal on public.meetings
  for select to authenticated using (app.has_internal_client_access(client_id));
create policy meeting_transcripts_select_internal on public.meeting_transcripts
  for select to authenticated using (
    exists (select 1 from public.meetings m
             where m.id = meeting_id and app.has_internal_client_access(m.client_id))
  );
create policy meeting_proposals_select_internal on public.meeting_proposals
  for select to authenticated using (app.has_internal_client_access(client_id));

revoke all on table public.meetings, public.meeting_transcripts, public.meeting_proposals
  from anon, authenticated;
grant select on table public.meetings, public.meeting_transcripts, public.meeting_proposals
  to authenticated;

revoke execute on function
  app.is_recording_ref(text),
  app.require_meeting(uuid)
from public, anon, authenticated;

revoke execute on function
  public.create_meeting(uuid, text, timestamptz, timestamptz, jsonb, text),
  public.save_meeting_transcript(uuid, text),
  public.request_meeting_extraction(uuid),
  public.request_meeting_transcription(uuid),
  public.accept_meeting_proposal(uuid, text),
  public.reject_meeting_proposal(uuid)
from public, anon;
grant execute on function
  public.create_meeting(uuid, text, timestamptz, timestamptz, jsonb, text),
  public.save_meeting_transcript(uuid, text),
  public.request_meeting_extraction(uuid),
  public.request_meeting_transcription(uuid),
  public.accept_meeting_proposal(uuid, text),
  public.reject_meeting_proposal(uuid)
to authenticated;

revoke execute on function
  worker.meeting_for_job(uuid, text, integer),
  worker.lease_for_completion(uuid, text, integer, text),
  worker.finish_job(uuid, jsonb),
  worker.complete_meeting_extraction(uuid, text, integer, jsonb),
  worker.complete_meeting_transcription(uuid, text, integer, jsonb)
from public, anon, authenticated;
grant execute on function
  worker.meeting_for_job(uuid, text, integer),
  worker.complete_meeting_extraction(uuid, text, integer, jsonb),
  worker.complete_meeting_transcription(uuid, text, integer, jsonb)
to jmos_worker;
