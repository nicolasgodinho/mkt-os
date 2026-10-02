import 'server-only';
import { z } from 'zod';
import { createSupabaseReader } from '@/lib/supabase/server';
import {
  approvalRequestSchema,
  commentSchema,
  decisionSchema,
  portalApprovalSchema,
  type ApprovalDecision,
  type ApprovalRequest,
  type ApprovalStatus,
  type Comment,
  type PortalApproval,
} from './model';

/**
 * Collaboration reads with the user's session. RLS decides: clients see their requests, the
 * revisions sent to them and client-visible comments; internal staff see everything of their
 * clients (tests/acceptance/increment-6).
 */

class CollabDataError extends Error {
  constructor(operation: string, code: string | undefined) {
    super(`collaboration data access failed: ${operation} (${code ?? 'unknown'})`);
    this.name = 'CollabDataError';
  }
}

async function reader() {
  const supabase = await createSupabaseReader();
  if (supabase === null) throw new CollabDataError('client unavailable', 'not_configured');
  return supabase;
}

const REQUEST_COLUMNS =
  'id, client_id, content_id, revision_id, status, requested_at, due_at, decided_at';

export async function listContentApprovals(contentId: string): Promise<ApprovalRequest[]> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('approval_requests')
    .select(REQUEST_COLUMNS)
    .eq('content_id', contentId)
    .order('requested_at', { ascending: false });
  if (error !== null) throw new CollabDataError('content approvals', error.code);
  return z.array(approvalRequestSchema).parse(data);
}

export async function listClientApprovals(
  clientIds: readonly string[],
  status: ApprovalStatus | null,
): Promise<ApprovalRequest[]> {
  if (clientIds.length === 0) return [];
  const supabase = await reader();
  let query = supabase
    .from('approval_requests')
    .select(REQUEST_COLUMNS)
    .in('client_id', [...clientIds]);
  if (status !== null) query = query.eq('status', status);
  const { data, error } = await query.order('requested_at', { ascending: false }).limit(200);
  if (error !== null) throw new CollabDataError('approvals', error.code);
  return z.array(approvalRequestSchema).parse(data);
}

/** Titles of the given contents (internal staff only: clients cannot read `contents`). */
export async function contentTitles(contentIds: readonly string[]): Promise<Map<string, string>> {
  if (contentIds.length === 0) return new Map();
  const supabase = await reader();
  const { data, error } = await supabase
    .from('contents')
    .select('id, title')
    .in('id', [...contentIds]);
  if (error !== null) throw new CollabDataError('content titles', error.code);
  return new Map(
    z
      .array(z.object({ id: z.uuid(), title: z.string() }))
      .parse(data)
      .map((row) => [row.id, row.title]),
  );
}

export async function getApprovalRequest(requestId: string): Promise<ApprovalRequest | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('approval_requests')
    .select(REQUEST_COLUMNS)
    .eq('id', requestId)
    .maybeSingle();
  if (error !== null) throw new CollabDataError('approval request', error.code);
  return data === null ? null : approvalRequestSchema.parse(data);
}

export async function getDecision(requestId: string): Promise<ApprovalDecision | null> {
  const supabase = await reader();
  const { data, error } = await supabase
    .from('approval_decisions')
    .select('approval_request_id, decision, comment, decided_at')
    .eq('approval_request_id', requestId)
    .maybeSingle();
  if (error !== null) throw new CollabDataError('decision', error.code);
  return data === null ? null : decisionSchema.parse(data);
}

export async function portalApprovals(clientId: string): Promise<PortalApproval[]> {
  const supabase = await reader();
  const result = await supabase.rpc('portal_approvals', { p_client_id: clientId });
  if (result.error !== null) throw new CollabDataError('portal approvals', result.error.code);
  return z.array(portalApprovalSchema).parse(result.data);
}

/** Comments on a content the caller can read (RLS hides internal threads from clients). */
export async function listComments(contentId: string): Promise<Comment[]> {
  const supabase = await reader();
  const threads = await supabase
    .from('threads')
    .select('id, visibility')
    .eq('target_type', 'content')
    .eq('target_id', contentId);
  if (threads.error !== null) throw new CollabDataError('threads', threads.error.code);
  const parsedThreads = z
    .array(z.object({ id: z.uuid(), visibility: z.enum(['internal', 'client']) }))
    .parse(threads.data);
  if (parsedThreads.length === 0) return [];
  const visibility = new Map(parsedThreads.map((thread) => [thread.id, thread.visibility]));
  const { data, error } = await supabase
    .from('comments')
    .select('id, thread_id, author_id, author_name, body, created_at')
    .in('thread_id', [...visibility.keys()])
    .order('created_at');
  if (error !== null) throw new CollabDataError('comments', error.code);
  return z
    .array(
      z.object({
        id: z.uuid(),
        thread_id: z.uuid(),
        author_id: z.uuid(),
        author_name: z.string(),
        body: z.string(),
        created_at: z.string(),
      }),
    )
    .parse(data)
    .map((row) =>
      commentSchema.parse({ ...row, visibility: visibility.get(row.thread_id) ?? 'client' }),
    );
}
