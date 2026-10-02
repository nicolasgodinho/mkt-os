import 'server-only';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  meetingJobSchema,
  meetingSchema,
  proposalSchema,
  transcriptSchema,
  type Meeting,
  type MeetingJob,
  type MeetingProposal,
  type MeetingTranscript,
} from './model';

/** Meeting reads with the user's session: RLS returns rows to internal staff only. */

class MeetingDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`meeting data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'MeetingDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new MeetingDataError('client unavailable', 'not_configured');
  return supabase;
}

const MEETING_COLUMNS =
  'id, title, starts_at, ends_at, participants, recording_ref, processing_status, transcript_source_id';

export async function listMeetings(clientId: string): Promise<Meeting[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('meetings')
    .select(MEETING_COLUMNS)
    .eq('client_id', clientId)
    .order('starts_at', { ascending: false })
    .limit(100);
  if (error !== null) throw new MeetingDataError('meetings', error.code);
  return z.array(meetingSchema).parse(data);
}

export async function getMeeting(clientId: string, meetingId: string): Promise<Meeting | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('meetings')
    .select(MEETING_COLUMNS)
    .eq('client_id', clientId)
    .eq('id', meetingId)
    .maybeSingle();
  if (error !== null) throw new MeetingDataError('meeting', error.code);
  return data === null ? null : meetingSchema.parse(data);
}

export async function getLatestTranscript(meetingId: string): Promise<MeetingTranscript | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('meeting_transcripts')
    .select('revision, text, origin, created_at')
    .eq('meeting_id', meetingId)
    .order('revision', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error !== null) throw new MeetingDataError('transcript', error.code);
  return data === null ? null : transcriptSchema.parse(data);
}

export async function listProposals(meetingId: string): Promise<MeetingProposal[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('meeting_proposals')
    .select(
      'id, kind, statement, rule_type, subject, confidence, evidence_quote, time_ref, status, accepted_item_id, transcript_revision',
    )
    .eq('meeting_id', meetingId)
    .order('transcript_revision', { ascending: false })
    .order('created_at');
  if (error !== null) throw new MeetingDataError('proposals', error.code);
  return z.array(proposalSchema).parse(data);
}

/** Latest jobs about this meeting (jobs reference the meeting in their input). */
export async function listMeetingJobs(meetingId: string): Promise<MeetingJob[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('jobs')
    .select('id, type, status, last_error, created_at')
    .eq('input->>meeting_id', meetingId)
    .order('created_at', { ascending: false })
    .limit(5);
  if (error !== null) throw new MeetingDataError('meeting jobs', error.code);
  return z.array(meetingJobSchema).parse(data);
}
