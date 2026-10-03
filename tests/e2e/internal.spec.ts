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

  test('pages carry a nonce-based CSP that the app runs under without violations', async ({
    page,
  }) => {
    const violations: string[] = [];
    page.on('console', (message) => {
      if (/Content Security Policy|Content-Security-Policy/i.test(message.text())) {
        violations.push(message.text());
      }
    });
    const first = await page.goto('/login');
    const policy = first?.headers()['content-security-policy'] ?? '';
    expect(policy).toMatch(/script-src 'self' 'nonce-[A-Za-z0-9+/=]+' 'strict-dynamic'/);
    expect(policy).toContain("frame-ancestors 'none'");
    expect(policy).toContain("object-src 'none'");
    expect(policy).not.toContain('unsafe-eval');

    // A new nonce per request.
    const second = await page.request.get('/login');
    expect(second.headers()['content-security-policy']).not.toBe(policy);

    // Every script carries this response's nonce, the Next.js client boots, nothing is blocked.
    const nonce = /'nonce-([A-Za-z0-9+/=]+)'/.exec(policy)?.[1];
    const scriptNonces = await page.evaluate(() =>
      Array.from(document.querySelectorAll('script'), (script) => script.nonce),
    );
    expect(scriptNonces.length).toBeGreaterThan(0);
    expect(new Set(scriptNonces)).toEqual(new Set([nonce]));
    await page.waitForFunction(() => 'next' in window);
    await page.waitForLoadState('networkidle');
    expect(violations).toEqual([]);
  });
});
