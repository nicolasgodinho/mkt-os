import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';
import { BUSINESS_UTC_OFFSET } from '../brain/model';

/**
 * Calendar and publication contract (tests/acceptance/increment-7/README.md) as seen by the web
 * app. Display and date helpers only: the database decides visibility and every change.
 */

export const EVENT_TYPES = [
  'publication',
  'production_deadline',
  'approval_deadline',
  'meeting',
] as const;
export type EventType = (typeof EVENT_TYPES)[number];

export const EVENT_TYPE: Record<EventType, { label: string; tone: StatusTone }> = {
  publication: { label: 'Publicação', tone: 'success' },
  production_deadline: { label: 'Prazo de produção', tone: 'warning' },
  approval_deadline: { label: 'Prazo de aprovação', tone: 'info' },
  meeting: { label: 'Reunião', tone: 'neutral' },
};

export const calendarEventSchema = z.object({
  event_type: z.enum(EVENT_TYPES),
  client_id: z.uuid(),
  entity_id: z.uuid(),
  content_id: z.uuid().nullable(),
  title: z.string(),
  starts_at: z.string(),
  status: z.string(),
  date_field: z.string(),
});
export type CalendarEvent = z.infer<typeof calendarEventSchema>;

export const PUBLICATION_STATUSES = [
  'draft',
  'scheduled',
  'publishing',
  'published',
  'failed',
  'retrying',
  'canceled',
] as const;
export type PublicationStatus = (typeof PUBLICATION_STATUSES)[number];

export const PUBLICATION_STATUS: Record<PublicationStatus, { label: string; tone: StatusTone }> = {
  draft: { label: 'Rascunho', tone: 'neutral' },
  scheduled: { label: 'Agendada', tone: 'info' },
  publishing: { label: 'Publicando', tone: 'info' },
  published: { label: 'Publicada', tone: 'success' },
  failed: { label: 'Falhou', tone: 'danger' },
  retrying: { label: 'Tentando de novo', tone: 'warning' },
  canceled: { label: 'Cancelada', tone: 'neutral' },
};

export const publicationSchema = z.object({
  id: z.uuid(),
  client_id: z.uuid(),
  content_id: z.uuid(),
  revision_id: z.uuid(),
  channel: z.string(),
  scheduled_at: z.string().nullable(),
  published_at: z.string().nullable(),
  remote_url: z.string().nullable(),
  status: z.enum(PUBLICATION_STATUSES),
});
export type Publication = z.infer<typeof publicationSchema>;

const BUSINESS_TIME_ZONE = 'America/Sao_Paulo';
const DAY_FORMAT = new Intl.DateTimeFormat('en-CA', {
  timeZone: BUSINESS_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});
const TIME_FORMAT = new Intl.DateTimeFormat('pt-BR', {
  timeZone: BUSINESS_TIME_ZONE,
  hour: '2-digit',
  minute: '2-digit',
});
const DATE_TIME_LOCAL = new Intl.DateTimeFormat('en-CA', {
  timeZone: BUSINESS_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});

/** The business-timezone calendar day (`YYYY-MM-DD`) of an instant. */
export function businessDay(value: string | Date): string {
  return DAY_FORMAT.format(typeof value === 'string' ? new Date(value) : value);
}

/** `HH:mm` in the business timezone. */
export function businessTime(value: string): string {
  return TIME_FORMAT.format(new Date(value));
}

/** `2026-10-05T14:30` (a `datetime-local` input) → an instant in the business timezone. */
export function toBusinessDateTime(value: string): string | null {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value) ? `${value}:00${BUSINESS_UTC_OFFSET}` : null;
}

/** An instant → the value a `datetime-local` input shows in the business timezone. */
export function toDateTimeLocal(value: string | null): string {
  if (value === null) return '';
  const parts = Object.fromEntries(
    DATE_TIME_LOCAL.formatToParts(new Date(value)).map((part) => [part.type, part.value]),
  );
  return `${parts.year ?? ''}-${parts.month ?? ''}-${parts.day ?? ''}T${parts.hour ?? ''}:${parts.minute ?? ''}`;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** `[now, now + days)` as instants, for "next N days" lists. */
export function upcomingRange(days: number, now: Date = new Date()): { from: string; to: string } {
  return {
    from: now.toISOString(),
    to: new Date(now.getTime() + days * DAY_MS).toISOString(),
  };
}

const MONTH = /^(\d{4})-(0[1-9]|1[0-2])$/;

/** A valid `YYYY-MM` from the URL, or the current business month. */
export function parseMonth(raw: string | undefined, now: Date): string {
  return raw !== undefined && MONTH.test(raw) ? raw : businessDay(now).slice(0, 7);
}

export function shiftMonth(month: string, delta: number): string {
  const [year, index] = month.split('-').map(Number) as [number, number];
  const date = new Date(Date.UTC(year, index - 1 + delta, 1));
  return `${date.getUTCFullYear().toString()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
}

/** The instants that bound a business month: `[from, to)`. */
export function monthRange(month: string): { from: string; to: string } {
  return {
    from: `${month}-01T00:00:00${BUSINESS_UTC_OFFSET}`,
    to: `${shiftMonth(month, 1)}-01T00:00:00${BUSINESS_UTC_OFFSET}`,
  };
}

/** Weeks (Monday first) covering a month, as `YYYY-MM-DD` days; days of other months included. */
export function monthGrid(month: string): string[][] {
  const [year, index] = month.split('-').map(Number) as [number, number];
  const first = new Date(Date.UTC(year, index - 1, 1));
  const start = new Date(first);
  start.setUTCDate(1 - ((first.getUTCDay() + 6) % 7));
  const weeks: string[][] = [];
  const cursor = new Date(start);
  do {
    const week: string[] = [];
    for (let day = 0; day < 7; day += 1) {
      week.push(cursor.toISOString().slice(0, 10));
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    weeks.push(week);
  } while (cursor.getUTCMonth() === index - 1);
  return weeks;
}

export function groupByDay(events: readonly CalendarEvent[]): Map<string, CalendarEvent[]> {
  const days = new Map<string, CalendarEvent[]>();
  for (const event of events) {
    const day = businessDay(event.starts_at);
    days.set(day, [...(days.get(day) ?? []), event]);
  }
  return days;
}

export const MONTH_NAMES = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
] as const;

export function monthLabel(month: string): string {
  const [year, index] = month.split('-').map(Number) as [number, number];
  return `${MONTH_NAMES[index - 1] ?? ''} de ${year.toString()}`;
}

/** `2026-10-05` → `seg., 05/10`. */
export function dayLabel(day: string): string {
  const [year, month, date] = day.split('-').map(Number) as [number, number, number];
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: 'UTC',
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
  }).format(new Date(Date.UTC(year, month - 1, date)));
}
