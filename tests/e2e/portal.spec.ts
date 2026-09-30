import { expect, test } from '@playwright/test';

test.describe('client portal shell (mobile)', () => {
  test('renders the mobile portal without any internal navigation', async ({ page }) => {
    await page.goto('/portal');

    await expect(page.getByRole('heading', { level: 1, name: 'Início' })).toBeVisible();
    await expect(page.getByRole('navigation', { name: 'Navegação do portal' })).toBeVisible();

    // Portal boundary (docs/05, docs/07 §14): no internal navigation or internal-only modules.
    await expect(page.getByRole('navigation', { name: 'Navegação principal' })).toHaveCount(0);
    for (const internalOnly of ['Automações', 'Configurações', 'Inteligência']) {
      await expect(page.getByText(internalOnly, { exact: true })).toHaveCount(0);
    }
  });

  test('fits a phone viewport without horizontal scrolling', async ({ page }) => {
    await page.goto('/portal');
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
});
