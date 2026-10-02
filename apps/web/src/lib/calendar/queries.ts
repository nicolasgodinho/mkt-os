import 'server-only';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  calendarEventSchema,
  publicationSchema,
  type CalendarEvent,
  type Publication,
} from './model';

/**
 * Calendar reads with the user's session. The database decides which events and publications
 * each caller sees (tests/acceptance/increment-7).
 */

class CalendarDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`calendar data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'CalendarDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new CalendarDataError('client unavailable', 'not_configured');
  return supabase;
}

export async function calendarEvents(
  from: string,
  to: string,
  clientId: string | null,
): Promise<CalendarEvent[]> {
  const supabase = await reader();
  const result = await supabase.rpc('calendar_events', {
    p_from: from,
    p_to: to,
    ...(clientId === null ? {} : { p_client_id: clientId }),
  });
  if (result.error !== null) throw new CalendarDataError('events', result.error.code);
  return z.array(calendarEventSchema).parse(result.data);
}

const PUBLICATION_COLUMNS =
  'id, client_id, content_id, revision_id, channel, scheduled_at, published_at, remote_url, status';

export async function listContentPublications(contentId: string): Promise<Publication[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('publications')
    .select(PUBLICATION_COLUMNS)
    .eq('content_id', contentId)
    .order('scheduled_at');
  if (error !== null) throw new CalendarDataError('publications', error.code);
  return z.array(publicationSchema).parse(data);
}

const schedulableSchema = z.object({
  id: z.uuid(),
  client_id: z.uuid(),
  title: z.string(),
  channel: z.string(),
});
export type SchedulableContent = z.infer<typeof schedulableSchema>;

/** The unscheduled backlog: client-approved content with no publication yet (internal only). */
export async function listSchedulableContents(
  clientIds: readonly string[],
): Promise<SchedulableContent[]> {
  if (clientIds.length === 0) return [];
  const supabase = await reader();
  const result = await supabase.rpc('unscheduled_contents', { p_client_ids: [...clientIds] });
  if (result.error !== null) throw new CalendarDataError('backlog', result.error.code);
  return z.array(schedulableSchema).parse(result.data);
}
