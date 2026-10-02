import { expect, test } from '@playwright/test';
import { ok, sendToClient, unique } from './support/content';
import { apiAs, login, requireSupabase, SEED } from './support/supabase';

// Client approval in the portal (Increment 6), on a phone. Every test sends its own fresh content
// to the client through the database API, so the seed stays reusable on re-runs.
const PORTAL_A = `/portal/${SEED.clients.a}`;

test.describe('client approval in the portal (mobile)', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('approver finds the request under "Precisa de você", comments and asks for changes', async ({
    page,
  }) => {
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const title = unique('Post para aprovar');
    const { contentId } = await sendToClient(admin, title);
    const internalNote = unique('Nota só da equipe');
    await ok(admin, 'add_comment', {
      p_target_type: 'content',
      p_target_id: contentId,
      p_body: internalNote,
      p_visibility: 'internal',
    });

    await login(page, SEED.users.approverA);
    const needsYou = page.getByRole('list', { name: 'Aguardando sua aprovação' });
    await needsYou.getByRole('link', { name: new RegExp(title) }).click();
    await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible();
    await expect(page.getByText('Sorriso de família')).toBeVisible();
    await expect(page.getByText(internalNote)).toHaveCount(0);

    const thread = page.getByRole('region', { name: 'Conversa com a equipe' });
    await thread.getByLabel('Comentário', { exact: true }).fill('Podemos trocar a foto?');
    await thread.getByRole('button', { name: 'Comentar' }).click();
    await expect(thread.getByText('Comentário enviado.')).toBeVisible();
    await expect(thread.getByText('Podemos trocar a foto?')).toBeVisible();

    const decision = page.getByRole('region', { name: 'Sua decisão' });
    await decision.getByLabel('Comentário para a equipe (opcional)').fill('Trocar a foto.');
    await decision.getByRole('button', { name: 'Pedir alterações' }).click();
    await expect(decision.getByText('Pedido de alterações enviado para a equipe.')).toBeVisible();
    await expect(page.getByText('Alterações pedidas').first()).toBeVisible();
    await expect(decision.getByRole('button', { name: 'Aprovar esta versão' })).toHaveCount(0);
  });

  test('approving records the decision on the exact revision', async ({ page }) => {
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const { requestId } = await sendToClient(admin, unique('Post aprovado'));

    await login(page, SEED.users.approverA);
    await page.goto(`${PORTAL_A}/approvals/${requestId}`);
    const decision = page.getByRole('region', { name: 'Sua decisão' });
    await decision.getByRole('button', { name: 'Aprovar esta versão' }).click();
    await expect(decision.getByText('Aprovado. Obrigado!')).toBeVisible();
    await expect(page.getByText('Aprovado pelo cliente').first()).toBeVisible();

    const again = await (
      await apiAs(requireSupabase(), SEED.users.approverA)
    ).rpc('decide_approval', { p_request_id: requestId, p_decision: 'approve' });
    expect(again.code).toBe('22023');
  });

  test('a request becomes canceled when the team changes the content', async ({ page }) => {
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const { contentId, requestId } = await sendToClient(admin, unique('Post alterado'));
    await ok(admin, 'save_content_payload', {
      p_content_id: contentId,
      p_payload: { body: 'Texto novo depois do envio.', cta: 'Agende pelo WhatsApp' },
    });

    await login(page, SEED.users.approverA);
    await page.goto(`${PORTAL_A}/approvals/${requestId}`);
    await expect(page.getByText(/Este pedido foi cancelado/)).toBeVisible();
    await expect(page.getByRole('button', { name: 'Aprovar esta versão' })).toHaveCount(0);
  });

  test('a collaborator can comment but cannot decide', async ({ page }) => {
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const { requestId } = await sendToClient(admin, unique('Post para colaborador'));

    await login(page, SEED.users.collaboratorA);
    await page.goto(`${PORTAL_A}/approvals/${requestId}`);
    await expect(page.getByRole('region', { name: 'Sua decisão' })).toHaveCount(0);
    await expect(
      page.getByRole('region', { name: 'Conversa com a equipe' }).getByRole('button', {
        name: 'Comentar',
      }),
    ).toBeVisible();

    const collaborator = await apiAs(requireSupabase(), SEED.users.collaboratorA);
    const forged = await collaborator.rpc('decide_approval', {
      p_request_id: requestId,
      p_decision: 'approve',
    });
    expect(forged.code).toBe('42501');

    // Leave no open request behind: the portal home of the seed client stays short on re-runs.
    await ok(admin, 'cancel_approval_request', { p_request_id: requestId });
  });
});
