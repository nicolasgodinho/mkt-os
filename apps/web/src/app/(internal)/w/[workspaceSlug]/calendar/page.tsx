import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Button, EmptyState, PageHeader, SelectField, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { requireSessionUser } from '@/lib/auth/session';
import { schedulePublication } from '@/lib/calendar/actions';
import {
  businessDay,
  businessTime,
  dayLabel,
  EVENT_TYPE,
  EVENT_TYPES,
  groupByDay,
  monthGrid,
  monthLabel,
  monthRange,
  parseMonth,
  shiftMonth,
  type CalendarEvent,
  type EventType,
} from '@/lib/calendar/model';
import { calendarEvents, listSchedulableContents } from '@/lib/calendar/queries';
import {
  getWorkspaceBySlug,
  getWorkspaceCapabilities,
  listWorkspaceClients,
} from '@/lib/identity/queries';

export const metadata: Metadata = { title: 'Calendário' };

const WEEKDAYS = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'] as const;

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

function eventHref(workspaceSlug: string, event: CalendarEvent): string {
  const client = `/w/${workspaceSlug}/clients/${event.client_id}`;
  if (event.event_type === 'meeting') return `${client}/meetings/${event.entity_id}`;
  return `${client}/content/items/${event.content_id ?? ''}`;
}

function EventLink({ workspaceSlug, event }: { workspaceSlug: string; event: CalendarEvent }) {
  return (
    <Link
      href={eventHref(workspaceSlug, event)}
      className="flex flex-col gap-0.5 rounded border-l-2 border-primary bg-surface-muted px-1.5 py-1 text-xs"
    >
      <span className="text-muted-foreground">
        {EVENT_TYPE[event.event_type].label} · {businessTime(event.starts_at)}
      </span>
      <span className="font-medium break-words">{event.title}</span>
    </Link>
  );
}

/**
 * Calendar (docs/07 §5): a projection of typed dated events over the visible clients (docs/06).
 * Each event opens its own record; dates change only through the record's typed actions.
 */
export default async function CalendarPage({
  params,
  searchParams,
}: {
  params: Promise<{ workspaceSlug: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { workspaceSlug } = await params;
  await requireSessionUser(`/w/${workspaceSlug}/calendar`);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  const capabilities = await getWorkspaceCapabilities(workspace.id);
  if (!capabilities.includes('client.view')) notFound();

  const query = await searchParams;
  const month = parseMonth(first(query.month), new Date());
  const view = first(query.view) === 'list' ? 'list' : 'month';
  const clients = await listWorkspaceClients(workspace.id);
  const clientId = clients.find((client) => client.id === first(query.client))?.id ?? null;
  const type: EventType | null = EVENT_TYPES.find((value) => value === first(query.type)) ?? null;

  const range = monthRange(month);
  const events = (await calendarEvents(range.from, range.to, clientId)).filter(
    (event) => type === null || event.event_type === type,
  );
  const byDay = groupByDay(events);
  const canSchedule = capabilities.includes('publication.schedule');
  const backlog = await listSchedulableContents(
    clientId === null ? clients.map((client) => client.id) : [clientId],
  );
  const clientName = new Map(clients.map((client) => [client.id, client.name]));

  const base = `/w/${workspace.slug}/calendar`;
  const link = (changes: Record<string, string | null>) => {
    const next = new URLSearchParams();
    const state: Record<string, string | null> = {
      month,
      view: view === 'month' ? null : view,
      client: clientId,
      type,
      ...changes,
    };
    for (const [key, value] of Object.entries(state)) if (value !== null) next.set(key, value);
    const text = next.toString();
    return text === '' ? base : `${base}?${text}`;
  };
  const today = businessDay(new Date());

  return (
    <>
      <PageHeader
        title="Calendário"
        description="Publicações, prazos de produção, prazos de aprovação e reuniões."
      />

      <form method="get" action={base} className="mb-4 flex flex-wrap items-end gap-3">
        <input type="hidden" name="month" value={month} />
        {view === 'list' ? <input type="hidden" name="view" value="list" /> : null}
        <SelectField
          id="calendar-client"
          name="client"
          label="Cliente"
          defaultValue={clientId ?? ''}
          options={[
            { value: '', label: 'Todos os clientes' },
            ...clients.map((client) => ({ value: client.id, label: client.name })),
          ]}
        />
        <SelectField
          id="calendar-type"
          name="type"
          label="Tipo de evento"
          defaultValue={type ?? ''}
          options={[
            { value: '', label: 'Todos os tipos' },
            ...EVENT_TYPES.map((value) => ({ value, label: EVENT_TYPE[value].label })),
          ]}
        />
        <Button type="submit" variant="secondary">
          Filtrar
        </Button>
      </form>

      <nav aria-label="Período" className="mb-4 flex flex-wrap items-center gap-2">
        <Link href={link({ month: shiftMonth(month, -1) })} className="text-sm text-primary">
          ← Mês anterior
        </Link>
        <h2 className="min-w-40 text-center text-sm font-medium capitalize">{monthLabel(month)}</h2>
        <Link href={link({ month: shiftMonth(month, 1) })} className="text-sm text-primary">
          Próximo mês →
        </Link>
        <span className="mx-2 text-muted-foreground" aria-hidden>
          |
        </span>
        <Link
          href={link({ view: null })}
          aria-current={view === 'month' ? 'page' : undefined}
          className={view === 'month' ? 'text-sm font-medium' : 'text-sm text-primary'}
        >
          Mês
        </Link>
        <Link
          href={link({ view: 'list' })}
          aria-current={view === 'list' ? 'page' : undefined}
          className={view === 'list' ? 'text-sm font-medium' : 'text-sm text-primary'}
        >
          Lista
        </Link>
      </nav>

      {view === 'month' ? (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[42rem] table-fixed border-collapse text-sm">
            <caption className="sr-only">Calendário de {monthLabel(month)}</caption>
            <thead>
              <tr>
                {WEEKDAYS.map((weekday) => (
                  <th
                    key={weekday}
                    scope="col"
                    className="py-1 text-xs font-medium text-muted-foreground"
                  >
                    {weekday}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {monthGrid(month).map((week) => (
                <tr key={week[0]}>
                  {week.map((day) => {
                    const dayEvents = byDay.get(day) ?? [];
                    const inMonth = day.startsWith(month);
                    return (
                      <td
                        key={day}
                        className={`h-24 border p-1 align-top ${inMonth ? '' : 'bg-surface-muted/50 text-muted-foreground'}`}
                      >
                        <span
                          className={`text-xs ${day === today ? 'rounded bg-primary px-1 text-primary-foreground' : ''}`}
                        >
                          {Number(day.slice(8)).toString()}
                        </span>
                        {dayEvents.length > 0 ? (
                          <ul className="mt-1 flex flex-col gap-1" aria-label={dayLabel(day)}>
                            {dayEvents.map((event) => (
                              <li key={`${event.event_type}-${event.entity_id}`}>
                                <EventLink workspaceSlug={workspace.slug} event={event} />
                              </li>
                            ))}
                          </ul>
                        ) : null}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : events.length === 0 ? (
        <EmptyState title="Nenhum evento neste mês" />
      ) : (
        <ol className="flex flex-col gap-4" aria-label="Eventos do mês">
          {[...byDay.entries()].map(([day, dayEvents]) => (
            <li key={day}>
              <h3 className="mb-1 text-sm font-medium capitalize">{dayLabel(day)}</h3>
              <ul className="flex flex-col gap-1" aria-label={dayLabel(day)}>
                {dayEvents.map((event) => (
                  <li
                    key={`${event.event_type}-${event.entity_id}`}
                    className="flex flex-wrap items-center gap-2 rounded-lg border bg-surface px-3 py-2"
                  >
                    <StatusBadge tone={EVENT_TYPE[event.event_type].tone}>
                      {EVENT_TYPE[event.event_type].label}
                    </StatusBadge>
                    <span className="text-xs text-muted-foreground">
                      {businessTime(event.starts_at)}
                    </span>
                    <Link
                      href={eventHref(workspace.slug, event)}
                      className="text-sm font-medium text-primary"
                    >
                      {event.title}
                    </Link>
                    <span className="text-xs text-muted-foreground">
                      {clientName.get(event.client_id) ?? ''}
                    </span>
                  </li>
                ))}
              </ul>
            </li>
          ))}
        </ol>
      )}

      <section aria-labelledby="backlog" className="mt-8">
        <h2 id="backlog" className="mb-2 text-sm font-medium">
          Aprovados sem data de publicação
        </h2>
        {backlog.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Nenhum conteúdo aprovado pelo cliente esperando data.
          </p>
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Aprovados sem data de publicação">
            {backlog.map((content) => (
              <li key={content.id} className="rounded-lg border bg-surface p-3">
                <div className="flex flex-wrap items-center gap-2">
                  <Link
                    href={`/w/${workspace.slug}/clients/${content.client_id}/content/items/${content.id}`}
                    className="text-sm font-medium text-primary"
                  >
                    {content.title}
                  </Link>
                  <span className="text-xs text-muted-foreground">
                    {clientName.get(content.client_id) ?? ''} · {content.channel}
                  </span>
                </div>
                {canSchedule ? (
                  <ActionForm
                    action={schedulePublication}
                    hidden={{
                      workspaceSlug: workspace.slug,
                      clientId: content.client_id,
                      contentId: content.id,
                    }}
                    buttons={[{ label: 'Agendar', ariaLabel: `Agendar ${content.title}` }]}
                    pendingLabel="Agendando…"
                    variant="inline"
                    className="mt-2"
                  >
                    <TextField
                      id={`schedule-${content.id}`}
                      name="scheduledAt"
                      type="datetime-local"
                      label="Data e hora da publicação"
                      required
                    />
                  </ActionForm>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
