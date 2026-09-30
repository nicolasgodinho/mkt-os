import { expect, test } from '@playwright/test';
import { expectNotFound, login, logout, requireSupabase, SEED } from './support/supabase';

// Client Portal with real sessions, on a phone. Skipped locally without the stack.
test.describe('client portal with a session (mobile)', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('approver: own portal, other clients and internal routes are not found, logout', async ({
    page,
  }) => {
    await login(page, SEED.users.approverA);
    await expect(page).toHaveURL(new RegExp(`/portal/${SEED.clients.a}$`));
    await expect(page.getByRole('heading', { level: 1, name: 'Cliente Demo A' })).toBeVisible();
    const areas = page.getByTestId('portal-areas');
    await expect(areas.getByText('Aprovações')).toBeVisible();
    await expect(areas.getByText('Solicitações')).toHaveCount(0);
    await expect(page.getByRole('navigation', { name: 'Navegação principal' })).toHaveCount(0);

    await expectNotFound(page, `/portal/${SEED.clients.b}`);
    await expectNotFound(page, `/portal/${SEED.clients.c}`);
    await expectNotFound(page, '/w/jansen/clients');
    await expect(page.getByText('Cliente Demo B')).toHaveCount(0);

    await page.goto(`/portal/${SEED.clients.a}`);
    await logout(page);
    await page.goto(`/portal/${SEED.clients.a}`);
    await expect(page).toHaveURL(/\/login/);
  });

  test('collaborator can submit requests but has no approvals area', async ({ page }) => {
    await login(page, SEED.users.collaboratorA);
    const areas = page.getByTestId('portal-areas');
    await expect(areas.getByText('Solicitações')).toBeVisible();
    await expect(areas.getByText('Aprovações')).toHaveCount(0);
  });

  test('viewer is read-only', async ({ page }) => {
    await login(page, SEED.users.viewerB);
    await expect(page).toHaveURL(new RegExp(`/portal/${SEED.clients.b}$`));
    const areas = page.getByTestId('portal-areas');
    await expect(areas.getByText('Conteúdo e calendário')).toBeVisible();
    await expect(areas.getByText('Aprovações')).toHaveCount(0);
    await expect(areas.getByText('Solicitações')).toHaveCount(0);
    await expectNotFound(page, `/portal/${SEED.clients.a}`);
  });

  test('a revoked client member gets no access', async ({ page }) => {
    await login(page, SEED.users.revokedClientA);
    await expect(page.getByRole('heading', { name: 'Sem acesso' })).toBeVisible();
    await expectNotFound(page, `/portal/${SEED.clients.a}`);
  });
});
