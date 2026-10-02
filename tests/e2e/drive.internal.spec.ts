import { expect, test } from '@playwright/test';
import { apiAs, expectNotFound, login, requireSupabase, SEED } from './support/supabase';

// Drive sync minimum (Increment 8) with real sessions. Skipped locally without the Supabase stack.
// No worker runs during E2E (docs/00 principle 7): requested syncs stay queued, which is exactly
// what the page must show.
const DRIVE_A = `/w/${SEED.workspaces.jansen}/clients/${SEED.clients.a}/drive`;
const SEED_CONNECTION = '35000000-0000-4000-8000-000000000001';

test.describe('drive', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('an admin sees the client folder, requests a sync, re-indexes, pauses and resumes', async ({
    page,
  }) => {
    await login(page, SEED.users.admin);
    await page.goto(DRIVE_A);
    const files = page.getByRole('list', { name: 'Arquivos do Drive' });
    await expect(files.getByText('Briefing Cliente A.docx')).toBeVisible();
    await expect(files.getByText('Tabela antiga.pdf')).toHaveCount(0);
    await page.getByRole('link', { name: 'Mostrar removidos' }).click();
    await expect(
      files
        .getByRole('listitem')
        .filter({ hasText: 'Tabela antiga.pdf' })
        .getByText('Removido do Drive'),
    ).toBeVisible();

    const connection = page.getByRole('region', { name: 'Conexão' });
    await connection.getByRole('button', { name: 'Sincronizar agora' }).click();
    await expect(connection.getByText('Sincronização solicitada.')).toBeVisible();
    await expect(connection.getByText('Sincronização na fila')).toBeVisible();

    await files.getByRole('button', { name: 'Indexar de novo Briefing Cliente A.docx' }).click();
    await expect(files.getByText('Arquivo marcado para indexar de novo.')).toBeVisible();

    await connection.getByRole('button', { name: 'Pausar' }).click();
    await expect(connection.getByText('Conexão pausada.')).toBeVisible();
    await expect(connection.getByRole('button', { name: 'Sincronizar agora' })).toHaveCount(0);
    await connection.getByRole('button', { name: 'Retomar' }).click();
    await expect(connection.getByText('Conexão retomada.')).toBeVisible();
    await expect(connection.getByRole('button', { name: 'Sincronizar agora' })).toBeVisible();
  });

  test('staff without integration.manage only read; clients never reach the registry', async ({
    page,
  }) => {
    await login(page, SEED.users.strategist);
    await page.goto(DRIVE_A);
    await expect(page.getByText('Briefing Cliente A.docx')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sincronizar agora' })).toHaveCount(0);

    const config = requireSupabase();
    const strategist = await apiAs(config, SEED.users.strategist);
    const forged = await strategist.rpc('request_drive_sync', { p_connection_id: SEED_CONNECTION });
    expect(forged.code).toBe('42501');

    const approver = await apiAs(config, SEED.users.approverA);
    expect((await approver.select('file_records', 'id')).data).toEqual([]);
    expect((await approver.select('integration_connections', 'id')).data).toEqual([]);
    const foreign = await approver.rpc('request_drive_sync', { p_connection_id: SEED_CONNECTION });
    expect(foreign.code).toBe('P0002');

    await page.context().clearCookies();
    await login(page, SEED.users.approverA);
    await expectNotFound(page, DRIVE_A);
  });
});
