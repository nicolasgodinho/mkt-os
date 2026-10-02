import { expect, test } from '@playwright/test';
import { clientApproved, ok, unique } from './support/content';
import { apiAs, login, requireSupabase, SEED } from './support/supabase';

// Portal calendar (Increment 7), on a phone. Each run schedules its own publication for
// Cliente Demo A through the API, so the test never depends on when the seed was loaded.
const DAY_MS = 24 * 60 * 60 * 1000;

test.describe('portal calendar (mobile)', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('the approver sees the next publications on the home and in the calendar', async ({
    page,
  }) => {
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const title = unique('Post da semana');
    const { contentId } = await clientApproved(admin, title);
    await ok(admin, 'schedule_publication', {
      p_content_id: contentId,
      p_scheduled_at: new Date(Date.now() + 2 * DAY_MS).toISOString(),
    });
    await ok(admin, 'set_production_deadline', {
      p_content_id: contentId,
      p_due_at: new Date(Date.now() + DAY_MS).toISOString(),
    });

    await login(page, SEED.users.approverA);
    await expect(
      page.getByRole('list', { name: 'Próximos 7 dias' }).getByText(title),
    ).toBeVisible();
    await page
      .getByTestId('portal-areas')
      .getByRole('link', { name: 'Conteúdo e calendário' })
      .click();
    await expect(page.getByRole('heading', { level: 1, name: 'Calendário' })).toBeVisible();
    const upcoming = page.getByRole('list', { name: 'Próximos 30 dias' });
    await expect(upcoming.getByText(title)).toHaveCount(1);
    await expect(page.getByText('Prazo de produção')).toHaveCount(0);
  });

  test('another client never sees Cliente Demo A publications', async ({ page }) => {
    await login(page, SEED.users.viewerB);
    await page.goto(`/portal/${SEED.clients.b}/calendar`);
    await expect(page.getByRole('heading', { level: 1, name: 'Calendário' })).toBeVisible();
    await expect(page.getByText('Post: dicas de escovação')).toHaveCount(0);
  });
});
