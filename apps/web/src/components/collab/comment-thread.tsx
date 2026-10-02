import { TextAreaField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { addComment } from '@/lib/collab/actions';
import type { Comment } from '@/lib/collab/model';
import { formatDateTime } from '@/lib/jobs/model';

interface CommentThreadProps {
  title: string;
  description?: string;
  comments: readonly Comment[];
  /** Hidden scope for the action (paths are rebuilt server-side from these ids). */
  scope: { clientId: string; contentId: string; workspaceSlug?: string; requestId?: string };
  visibility: 'internal' | 'client';
  canWrite: boolean;
  currentUserId: string;
}

function hiddenScope(scope: CommentThreadProps['scope']): Record<string, string> {
  const hidden: Record<string, string> = { clientId: scope.clientId, contentId: scope.contentId };
  if (scope.workspaceSlug !== undefined) hidden.workspaceSlug = scope.workspaceSlug;
  if (scope.requestId !== undefined) hidden.requestId = scope.requestId;
  return hidden;
}

/** CommentThread (docs/07 UI patterns): one visibility, newest last, with an add form. */
export function CommentThread({
  title,
  description,
  comments,
  scope,
  visibility,
  canWrite,
  currentUserId,
}: CommentThreadProps) {
  const headingId = `thread-${visibility}`;
  return (
    <section aria-labelledby={headingId} className="rounded-lg border bg-surface p-4">
      <h3 id={headingId} className="text-sm font-medium">
        {title}
      </h3>
      {description ? <p className="mt-1 text-xs text-muted-foreground">{description}</p> : null}
      {comments.length === 0 ? (
        <p className="mt-3 text-sm text-muted-foreground">Nenhum comentário ainda.</p>
      ) : (
        <ul className="mt-3 flex flex-col gap-2" aria-label={title}>
          {comments.map((comment) => (
            <li key={comment.id} className="rounded-md bg-surface-muted p-3 text-sm">
              <p className="text-xs text-muted-foreground">
                {comment.author_id === currentUserId
                  ? 'Você'
                  : comment.author_name || 'Participante'}{' '}
                · {formatDateTime(comment.created_at)}
              </p>
              <p className="mt-1 whitespace-pre-line">{comment.body}</p>
            </li>
          ))}
        </ul>
      )}
      {canWrite ? (
        <ActionForm
          action={addComment}
          hidden={hiddenScope(scope)}
          buttons={[{ label: 'Comentar', value: visibility }]}
          pendingLabel="Enviando…"
          resetOnSuccess
          className="mt-3"
        >
          <TextAreaField
            id={`comment-${visibility}`}
            name="body"
            label={visibility === 'internal' ? 'Comentário interno' : 'Comentário'}
            rows={2}
            maxLength={4000}
            required
          />
        </ActionForm>
      ) : null}
    </section>
  );
}
