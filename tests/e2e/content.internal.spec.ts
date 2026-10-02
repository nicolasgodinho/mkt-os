import { expect, test } from '@playwright/test';
import { apiAs, expectNotFound, login, requireSupabase, SEED } from './support/supabase';

// Content core (Increment 5) with real sessions. Skipped locally without the Supabase stack.
// The rule-validator flow uses Cliente Demo B, whose rules no other spec changes.
const CONTENT_A = `/w/${SEED.workspaces.jansen}/clients/${SEED.clients.a}/content`;
const CONTENT_B = `/w/${SEED.workspaces.jansen}/clients/${SEED.clients.b}/content`;
const B_PAUTA = '32000000-0000-4000-8000-0000000000b4';
const B_REVISION = '32000000-0000-4000-8000-0000000000b6';
const B_RULE = '32000000-0000-4000-8000-0000000000b3';

function unique(label: string): string {
  return `${label} e2e-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

test.describe('content core', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('a strategist writes a pauta, meets the Definition of Ready and starts a content', async ({
    page,
  }) => {
    const title = unique('Pauta de inverno');
    await login(page, SEED.users.strategist);
    await page.goto(CONTENT_A);
    await page.getByText('Nova pauta').click();
    await page.getByLabel('Título da pauta').fill(title);
    await page.getByRole('button', { name: 'Criar pauta' }).click();
    await page.getByRole('list', { name: 'Pautas' }).getByRole('link', { name: title }).click();

    const checklist = page.getByRole('list', { name: 'Checklist do Definition of Ready' });
    await expect(checklist.getByText('Falta')).toHaveCount(4);
    const brief = page.getByRole('region', { name: 'Briefing' });
    await brief.getByLabel('Objetivo').fill('Gerar agendamentos no inverno');
    await brief.getByLabel('Famílias com crianças').check();
    await brief.getByLabel('Mensagem').fill('Inverno também é tempo de cuidar do sorriso.');
    await brief.getByLabel('CTA').fill('Agende sua avaliação');
    await brief.getByRole('button', { name: 'Salvar e marcar pronta' }).click();
    await expect(brief.getByText('Pauta pronta para produção.')).toBeVisible();
    await expect(checklist.getByText('Falta')).toHaveCount(0);

    await page.getByText('Novo conteúdo').click();
    await page.getByLabel('Título do conteúdo').fill(unique('Post de inverno'));
    await page.getByLabel('Canal').fill('instagram');
    await page.getByLabel('Formato').fill('post');
    await page.getByRole('button', { name: 'Criar conteúdo' }).click();
    await expect(page.getByText('Conteúdo criado.')).toBeVisible();
  });

  test('a MUST_NOT violation blocks approval; approval targets the exact revision', async ({
    page,
  }) => {
    // Fresh content under review for every run (the seed must stay reusable on re-runs).
    const admin = await apiAs(requireSupabase(), SEED.users.admin);
    const created = await admin.rpc('create_content', {
      p_pauta_id: B_PAUTA,
      p_channel: 'linkedin',
      p_format: 'post',
      p_title: unique('Post com preço'),
    });
    const contentId = created.data as string;
    await admin.rpc('save_content_payload', {
      p_content_id: contentId,
      p_payload: { body: 'Planos a partir de R$ 29 por colaborador.' },
    });
    await admin.rpc('submit_for_internal_review', { p_content_id: contentId });

    await login(page, SEED.users.admin);
    await page.goto(`${CONTENT_B}/items/${contentId}`);
    const review = page.getByRole('region', { name: /Revisão interna/ });
    const rule = review
      .getByRole('list', { name: 'Validação de regras' })
      .getByRole('listitem')
      .filter({
        hasText: 'Nunca divulgar preços.',
      });
    const decision = page.getByRole('region', { name: 'Decisão da revisão interna' });
    const approve = decision.getByRole('button', { name: 'Aprovar esta revisão' });

    await rule.getByRole('button', { name: /^Viola:/ }).click();
    await expect(rule.getByText('Checagem registrada.')).toBeVisible();
    await expect(approve).toBeDisabled();

    // The text cites a price: the reviewer sends the content back to production.
    await decision.getByRole('button', { name: 'Pedir alterações' }).click();
    await expect(decision.getByText(/Alterações solicitadas/)).toBeVisible();
    await expect(page.getByText('Em produção', { exact: true }).first()).toBeVisible();

    const editor = page.getByRole('region', { name: 'Texto de trabalho' });
    await editor
      .getByLabel('Texto', { exact: true })
      .fill('Planos corporativos sob medida para a sua empresa.');
    await editor.getByRole('button', { name: 'Salvar e enviar para revisão' }).click();
    await expect(page.getByRole('heading', { name: /Revisão interna: revisão 2/ })).toBeVisible();

    const rule2 = page
      .getByRole('list', { name: 'Validação de regras' })
      .getByRole('listitem')
      .filter({ hasText: 'Nunca divulgar preços.' });
    await rule2.getByRole('button', { name: /^Atende:/ }).click();
    await expect(rule2.getByText('Checagem registrada.')).toBeVisible();
    await decision.getByRole('button', { name: 'Aprovar esta revisão' }).click();
    await expect(decision.getByText('Revisão aprovada internamente.')).toBeVisible();

    const history = page.getByRole('list', { name: 'Histórico de revisões' });
    await expect(
      history.getByRole('listitem').filter({ hasText: 'Revisão 2' }).getByText('Aprovada'),
    ).toBeVisible();
    await expect(
      history.getByRole('listitem').filter({ hasText: 'Revisão 1' }).getByText('Aprovada'),
    ).toHaveCount(0);
  });

  test('client users never reach content; revisions and checks are API-protected', async ({
    page,
  }) => {
    await login(page, SEED.users.approverA);
    await expectNotFound(page, CONTENT_A);

    const config = requireSupabase();
    const approver = await apiAs(config, SEED.users.approverA);
    expect((await approver.select('contents', 'id')).data).toEqual([]);

    const strategist = await apiAs(config, SEED.users.strategist);
    const check = await strategist.rpc('record_rule_check', {
      p_revision_id: B_REVISION,
      p_rule_id: B_RULE,
      p_result: 'pass',
    });
    expect(check.code).toBe('42501');

    const admin = await apiAs(config, SEED.users.admin);
    const forged = await admin.update('content_revisions', { payload: { body: 'x' } }, B_REVISION);
    expect(forged.code).toBe('42501');
  });
});
