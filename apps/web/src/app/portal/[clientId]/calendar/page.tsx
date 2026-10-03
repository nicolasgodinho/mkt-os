import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, PageHeader } from '@jmos/ui';
import { PortalEvent } from '@/components/calendar/portal-event';
import { dayLabel, groupByDay, upcomingRange } from '@/lib/calendar/model';
import { calendarEvents } from '@/lib/calendar/queries';
import { requirePortalContext } from '@/lib/portal/context';

export const metadata: Metadata = { title: 'Calendário' };

/** Portal calendar (docs/06 client navigation): the next 30 days of what concerns the client. */
export default async function PortalCalendarPage({
  params,
}: {
  params: Promise<{ clientId: string }>;
}) {
  const { clientId } = await params;
  const { client } = await requirePortalContext(clientId, `/portal/${clientId}/calendar`);
  const range = upcomingRange(30);
  const events = await calendarEvents(range.from, range.to, client.id);
  const byDay = groupByDay(events);

  return (
    <>
      <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
        <Link href={`/portal/${client.id}`}>{client.name}</Link>
      </nav>
      <PageHeader
        title="Calendário"
        description="Publicações e prazos de aprovação dos próximos 30 dias."
      />
      {events.length === 0 ? (
        <EmptyState title="Nada agendado para os próximos 30 dias" />
      ) : (
        <ol className="flex flex-col gap-4" aria-label="Próximos 30 dias">
          {[...byDay.entries()].map(([day, dayEvents]) => (
            <li key={day}>
              <h2 className="mb-1 text-sm font-medium capitalize">{dayLabel(day)}</h2>
              <ul className="flex flex-col gap-2" aria-label={dayLabel(day)}>
                {dayEvents.map((event) => (
                  <PortalEvent key={`${event.event_type}-${event.entity_id}`} event={event} />
                ))}
              </ul>
            </li>
          ))}
        </ol>
      )}
    </>
  );
}
