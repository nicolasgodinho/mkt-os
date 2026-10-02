import { expect, test } from '@playwright/test';
import { clientApproved, unique } from './support/content';
import { apiAs, login, requireSupabase, SEED } from './support/supabase';

// Calendar and publication schedule (Increment 7) with real sessions. Skipped locally without the
// Supabase stack. Each run schedules its own fresh client-approved content.
const CALENDAR = `/w/${SEED.workspaces.jansen}/calendar`;
const SEED_POST = 'Post: dicas de escovação';
const DAY_MS = 24 * 60 * 60 * 1000;
const BUSINESS_OFFSET_MS = 3 * 60 * 60 * 1000;

/** `YYYY-MM-DDTHH:mm` in the business timezone, `days` from now at the given hour. */
function businessDateTime(days: number, hour: string): string {
  const day = new Date(Date.now() + days * DAY_MS - BUSINESS_OFFSET_MS).toISOString().slice(0, 10);
  return `${day}T${hour}`;
}

test.describe('calendar and publication', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('client-approved content is scheduled from the backlog, moved and recorded as published', async ({
    page,
  }) => {
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const title = unique('Post agendado');
    await clientApproved(admin, title);
    const when = businessDateTime(2, '10:00');

    await login(page, SEED.users.admin);
    await page.goto(`${CALENDAR}?month=${when.slice(0, 7)}&view=list&client=${SEED.clients.a}`);
    const backlog = page.getByRole('list', { name: 'Aprovados sem data de publicação' });
    const item = backlog.getByRole('listitem').filter({ hasText: title });
    await item.getByLabel('Data e hora da publicação').fill(when);
    await item.getByRole('button', { name: `Agendar ${title}` }).click();

    const events = page.getByRole('list', { name: 'Eventos do mês' });
    await events.getByRole('link', { name: title }).click();
    const panel = page.getByRole('region', { name: 'Publicação', exact: true });
    const publication = panel.getByRole('list', { name: 'Publicações' }).getByRole('listitem');
    await expect(publication.getByText('Agendada')).toBeVisible();

    await publication.getByLabel('Nova data de publicação').fill(businessDateTime(3, '15:30'));
    await publication.getByRole('button', { name: 'Mudar data da publicação' }).click();
    await expect(publication.getByText('Data de publicação alterada.')).toBeVisible();

    await publication
      .getByLabel('Link da publicação (opcional)')
      .fill('https://instagram.com/p/e2e');
    await publication.getByRole('button', { name: 'Registrar como publicada' }).click();
    await expect(publication.getByText('Publicada', { exact: true })).toBeVisible();
    await expect(publication.getByRole('link', { name: 'Ver publicação' })).toBeVisible();
  });

  test('the month view shows typed events; the API boundary holds', async ({ page }) => {
    const config = requireSupabase();
    const admin = await apiAs(config, SEED.users.admin);
    const seeded = (await admin.select('publications', 'id,scheduled_at')).data as {
      id: string;
      scheduled_at: string;
    }[];
    const seedPublication = seeded.find((row) => row.id === '34000000-0000-4000-8000-000000000041');
    expect(seedPublication).toBeDefined();
    const month = new Date(
      new Date(seedPublication?.scheduled_at ?? '').getTime() - BUSINESS_OFFSET_MS,
    )
      .toISOString()
      .slice(0, 7);

    await login(page, SEED.users.admin);
    await page.goto(`${CALENDAR}?month=${month}&client=${SEED.clients.a}`);
    await expect(
      page.getByRole('link', { name: new RegExp(`Publicação.*${SEED_POST}`) }),
    ).toBeVisible();

    const strategist = await apiAs(config, SEED.users.strategist);
    const forged = await strategist.rpc('schedule_publication', {
      p_content_id: '32000000-0000-4000-8000-000000000011',
      p_scheduled_at: new Date(Date.now() + 2 * DAY_MS).toISOString(),
    });
    expect(forged.code).toBe('42501');

    const approver = await apiAs(config, SEED.users.approverA);
    const visible = await approver.rpc('calendar_events', {
      p_from: new Date().toISOString(),
      p_to: new Date(Date.now() + 30 * DAY_MS).toISOString(),
    });
    const types = new Set((visible.data as { event_type: string }[]).map((row) => row.event_type));
    expect(types.has('publication')).toBe(true);
    expect(types.has('production_deadline')).toBe(false);
    expect(types.has('meeting')).toBe(false);
  });
});
