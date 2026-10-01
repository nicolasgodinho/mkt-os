import { expect, test } from '@playwright/test';

// Unauthenticated behavior of the internal surface. Runs everywhere (no Supabase needed).
test.describe('internal surface without a session', () => {
  test('protected routes redirect to the login page', async ({ page }) => {
    await page.goto('/w/jansen/clients');
    await expect(page).toHaveURL(/\/login\?next=%2Fw%2Fjansen/);
    await expect(page.getByRole('heading', { level: 1, name: 'Entrar' })).toBeVisible();

    await page.goto('/');
    await expect(page).toHaveURL(/\/login/);
  });

  test('the login page shows no internal navigation or data', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByRole('navigation', { name: 'Navegação principal' })).toHaveCount(0);
    await expect(page.getByText('Clientes', { exact: true })).toHaveCount(0);
  });

  test('sends baseline security headers', async ({ request }) => {
    const response = await request.get('/login');
    expect(response.headers()['x-frame-options']).toBe('DENY');
    expect(response.headers()['x-content-type-options']).toBe('nosniff');
    expect(response.headers()['x-powered-by']).toBeUndefined();
  });
});
