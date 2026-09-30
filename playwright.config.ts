import { defineConfig, devices } from '@playwright/test';

// Uncommon default so a developer's own dev servers (3000, 3100, …) never collide with E2E.
const PORT = Number(process.env.JMOS_E2E_PORT ?? 3917);
const baseURL = `http://127.0.0.1:${String(PORT)}`;
const isCI = process.env.CI !== undefined;

/**
 * E2E runs against the production build (`pnpm build` first). No AI Worker runs during E2E on
 * purpose: the web app must never depend on it (docs/00 principle 7).
 */
export default defineConfig({
  testDir: 'tests/e2e',
  forbidOnly: isCI,
  retries: isCI ? 1 : 0,
  reporter: isCI ? [['github'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'internal-desktop',
      testMatch: /internal\.spec\.ts|health\.spec\.ts/,
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'portal-mobile',
      testMatch: /portal\.spec\.ts/,
      use: { ...devices['Pixel 7'] },
    },
  ],
  webServer: {
    command: `pnpm --filter @jmos/web exec next start --hostname 127.0.0.1 --port ${String(PORT)}`,
    url: `${baseURL}/api/health`,
    reuseExistingServer: !isCI,
    timeout: 120_000,
  },
});
