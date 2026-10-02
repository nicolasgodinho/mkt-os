import { expect, test } from '@playwright/test';
import { apiAs, expectNotFound, login, requireSupabase, SEED } from './support/supabase';

// Job center (Increment 3) with real sessions. Skipped locally without the Supabase stack.
const CENTER = `/w/${SEED.workspaces.jansen}/automations`;

test.describe('job center', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('an admin requests a healthcheck and sees it queued while no worker is online', async ({
    page,
  }) => {
    await login(page, SEED.users.admin);
    await page
      .getByRole('navigation', { name: 'Navegação principal' })
      .getByRole('link', { name: 'Automações' })
      .click();
    await expect(page).toHaveURL(CENTER);
    await expect(page.getByRole('heading', { level: 1, name: 'Automações' })).toBeVisible();

    const tests = page.getByRole('region', { name: 'Testes do sistema' });
    await tests.getByRole('button', { name: 'Testar worker (healthcheck)' }).click();
    await expect(tests.getByText('Job enviado para a fila.')).toBeVisible();

    await page.goto(`${CENTER}?status=queued`);
    const queued = page.getByRole('list', { name: 'Jobs' }).getByRole('listitem');
    await expect(queued.filter({ hasText: 'system.healthcheck.v1' }).first()).toBeVisible();
    await expect(
      queued
        .filter({ hasText: 'system.healthcheck.v1' })
        .first()
        .getByRole('button', { name: /Cancelar job/ }),
    ).toBeVisible();
  });

  test('a strategist sees the job center but cannot operate jobs', async ({ page }) => {
    await login(page, SEED.users.strategist);
    await page.goto(CENTER);
    await expect(page.getByRole('heading', { level: 1, name: 'Automações' })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Testes do sistema' })).toHaveCount(0);
    await expect(page.getByRole('button', { name: /Cancelar job|Tentar de novo job/ })).toHaveCount(
      0,
    );
  });

  test('client users and contributors without a grant never reach the job center', async ({
    page,
  }) => {
    await login(page, SEED.users.approverA);
    await expectNotFound(page, CENTER);
    await page.context().clearCookies();
    await login(page, SEED.users.contributor);
    await expectNotFound(page, CENTER);
  });

  test('the job center API boundary holds for raw calls', async () => {
    const config = requireSupabase();
    const strategist = await apiAs(config, SEED.users.strategist);
    const denied = await strategist.rpc('request_system_job', {
      p_workspace_id: SEED.workspaceIds.jansen,
      p_type: 'system.healthcheck',
      p_idempotency_key: `e2e-strategist-${Date.now().toString(36)}`,
    });
    expect(denied.code).toBe('42501');

    const approver = await apiAs(config, SEED.users.approverA);
    expect((await approver.select('jobs', 'id')).data).toEqual([]);
    expect(
      (await approver.rpc('job_center_summary', { p_workspace_id: SEED.workspaceIds.jansen })).data,
    ).toEqual([]);

    const other = await apiAs(config, SEED.users.otherAdmin);
    const foreign = await other.rpc('request_system_job', {
      p_workspace_id: SEED.workspaceIds.jansen,
      p_type: 'system.healthcheck',
      p_idempotency_key: `e2e-foreign-${Date.now().toString(36)}`,
    });
    expect(foreign.code).toBe('P0002');
  });
});
