import { expect, test } from '@playwright/test';

// Unauthenticated behavior of the client portal on a phone. Runs everywhere.
test.describe('client portal without a session (mobile)', () => {
  test('the portal redirects to the login page', async ({ page }) => {
    await page.goto('/portal');
    await expect(page).toHaveURL(/\/login\?next=%2Fportal/);
    await page.goto('/portal/20000000-0000-4000-8000-00000000000a');
    await expect(page).toHaveURL(/\/login/);
  });

  test('the login page fits a phone viewport without horizontal scrolling', async ({ page }) => {
    await page.goto('/login');
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
});
