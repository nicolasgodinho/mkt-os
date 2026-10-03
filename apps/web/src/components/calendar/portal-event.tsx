import Link from 'next/link';
import { StatusBadge } from '@jmos/ui';
import {
  businessTime,
  EVENT_TYPE,
  PUBLICATION_STATUS,
  PUBLICATION_STATUSES,
  type CalendarEvent,
} from '@/lib/calendar/model';

function statusLabel(event: CalendarEvent): string | null {
  if (event.event_type !== 'publication') return null;
  const status = PUBLICATION_STATUSES.find((value) => value === event.status);
  return status === undefined ? null : PUBLICATION_STATUS[status].label;
}

/** One calendar event as a client sees it; approval deadlines open the approval screen. */
export function PortalEvent({ event }: { event: CalendarEvent }) {
  const status = statusLabel(event);
  const body = (
    <>
      <span className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={EVENT_TYPE[event.event_type].tone}>
          {EVENT_TYPE[event.event_type].label}
        </StatusBadge>
        <span className="text-xs text-muted-foreground">{businessTime(event.starts_at)}</span>
        {status === null ? null : <span className="text-xs text-muted-foreground">{status}</span>}
      </span>
      <span className="mt-1 block font-medium">{event.title}</span>
    </>
  );
  return (
    <li>
      {event.event_type === 'approval_deadline' ? (
        <Link
          href={`/portal/${event.client_id}/approvals/${event.entity_id}`}
          className="block rounded-lg border bg-surface px-4 py-3"
        >
          {body}
        </Link>
      ) : (
        <div className="rounded-lg border bg-surface px-4 py-3">{body}</div>
      )}
    </li>
  );
}
