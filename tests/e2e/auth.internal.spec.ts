import { expect, test } from '@playwright/test';
import { expectNotFound, login, logout, requireSupabase, SEED } from './support/supabase';

// Internal OS with real sessions (Supabase Auth + RLS). Skipped locally without the stack.
test.describe('internal shell with a session', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('admin: workspace, allowed clients, client context, other tenants and logout', async ({
    page,
  }) => {
    await login(page, SEED.users.admin);
    await expect(page).toHaveURL(/\/w\/jansen$/);
    await expect(page.getByTestId('current-workspace')).toHaveText('Jansen Company');

    await page.getByRole('link', { name: 'Clientes' }).click();
    await expect(page.getByRole('link', { name: 'Cliente Demo A' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Cliente Demo B' })).toBeVisible();
    await expect(page.getByText('Cliente Alternativo C')).toHaveCount(0);

    await page.getByRole('link', { name: 'Cliente Demo A' }).click();
    await expect(page.getByRole('heading', { level: 1, name: 'Cliente Demo A' })).toBeVisible();
    await expect(page.getByText('Gerenciar clientes')).toBeVisible();

    // Another workspace and another workspace's client are indistinguishable from nonexistent.
    await expectNotFound(page, `/w/${SEED.workspaces.other}`);
    await expectNotFound(page, `/w/jansen/clients/${SEED.clients.c}`);
    await expectNotFound(page, `/w/jansen/clients/${SEED.randomId}`);
    await expectNotFound(page, '/w/jansen/clients/not-a-uuid');
    await expect(page.getByText('Cliente Alternativo C')).toHaveCount(0);

    await page.goto('/w/jansen');
    await logout(page);
    await page.goto('/w/jansen/clients');
    await expect(page).toHaveURL(/\/login/);
  });

  test('contributor without an explicit grant sees no client (fail-closed)', async ({ page }) => {
    await login(page, SEED.users.contributor);
    await page.goto('/w/jansen/clients');
    await expect(page.getByRole('heading', { name: 'Nenhum cliente disponível' })).toBeVisible();
    await expectNotFound(page, `/w/jansen/clients/${SEED.clients.a}`);
  });

  test('a revoked member gets no access', async ({ page }) => {
    await login(page, SEED.users.revokedInternal);
    await expect(page.getByRole('heading', { name: 'Sem acesso' })).toBeVisible();
    await expectNotFound(page, '/w/jansen');
  });

  test('a client-side user cannot enter the internal surface', async ({ page }) => {
    await login(page, SEED.users.approverA);
    await expect(page).toHaveURL(new RegExp(`/portal/${SEED.clients.a}$`));
    await expectNotFound(page, '/w/jansen');
    await expectNotFound(page, `/w/jansen/clients/${SEED.clients.a}`);
  });
});
