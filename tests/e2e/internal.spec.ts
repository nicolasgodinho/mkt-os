import { expect, test } from '@playwright/test';

test.describe('internal shell (desktop)', () => {
  test('renders the internal navigation from docs/06 without linking to unbuilt modules', async ({
    page,
  }) => {
    await page.goto('/');

    await expect(page.getByRole('heading', { level: 1, name: 'Início' })).toBeVisible();
    const nav = page.getByRole('navigation', { name: 'Navegação principal' });
    await expect(nav.getByRole('link', { name: 'Início' })).toHaveAttribute('aria-current', 'page');

    // Unbuilt modules are visible as "em breve" but are not links (no fake pages).
    for (const label of ['Clientes', 'Aprovações', 'Configurações']) {
      await expect(nav.getByText(label, { exact: true })).toBeVisible();
      await expect(nav.getByRole('link', { name: label })).toHaveCount(0);
    }
  });

  test('sends baseline security headers', async ({ request }) => {
    const response = await request.get('/');
    expect(response.headers()['x-frame-options']).toBe('DENY');
    expect(response.headers()['x-content-type-options']).toBe('nosniff');
    expect(response.headers()['x-powered-by']).toBeUndefined();
  });
});
