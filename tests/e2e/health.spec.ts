import { expect, test } from '@playwright/test';

// docs/11 invariant 10 (AI offline resilience), foundation level: E2E runs with no AI Worker,
// and the web app stays healthy.
test('web health does not depend on the AI Worker', async ({ request }) => {
  const response = await request.get('/api/health');
  expect(response.status()).toBe(200);
  expect(response.headers()['cache-control']).toContain('no-store');
  expect(await response.json()).toMatchObject({ status: 'ok', service: 'web' });
});
