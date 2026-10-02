import { expect, test } from '@playwright/test';
import { login, requireSupabase, SEED } from './support/supabase';

// Portal calendar (Increment 7), on a phone. Reads only: the seed publication of Cliente Demo A.
const SEED_POST = 'Post: dicas de escovação';

test.describe('portal calendar (mobile)', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('the approver sees the next publications on the home and in the calendar', async ({
    page,
  }) => {
    await login(page, SEED.users.approverA);
    await expect(
      page.getByRole('list', { name: 'Próximos 7 dias' }).getByText(SEED_POST),
    ).toBeVisible();
    await page
      .getByTestId('portal-areas')
      .getByRole('link', { name: 'Conteúdo e calendário' })
      .click();
    await expect(page.getByRole('heading', { level: 1, name: 'Calendário' })).toBeVisible();
    await expect(
      page.getByRole('list', { name: 'Próximos 30 dias' }).getByText(SEED_POST),
    ).toBeVisible();
    await expect(page.getByText('Prazo de produção')).toHaveCount(0);
  });

  test('another client never sees it', async ({ page }) => {
    await login(page, SEED.users.viewerB);
    await page.goto(`/portal/${SEED.clients.b}/calendar`);
    await expect(page.getByRole('heading', { level: 1, name: 'Calendário' })).toBeVisible();
    await expect(page.getByText(SEED_POST)).toHaveCount(0);
  });
});
