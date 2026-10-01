import { expect, type Page, test } from '@playwright/test';
import { apiAs, expectNotFound, login, logout, requireSupabase, SEED } from './support/supabase';

// Client Brain (Increment 2) with real sessions. Skipped locally without the Supabase stack.
const BRAIN = `/w/${SEED.workspaces.jansen}/clients/${SEED.clients.a}/brain`;
const SEEDED = {
  trustedSource: '30000000-0000-4000-8000-000000000041',
  proposedRule: '30000000-0000-4000-8000-000000000083',
  proposedFact: '30000000-0000-4000-8000-000000000052',
};

/** Unique per run, so retries and repeated CI runs never collide on the shared database. */
function unique(label: string): string {
  return `${label} e2e-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

async function proposeRule(
  page: Page,
  rule: { type: string; subject: string; statement: string },
): Promise<void> {
  const form = page.getByRole('region', { name: 'Propor regra' });
  await form.getByLabel('Tipo').selectOption(rule.type);
  await form.getByLabel('Assunto (obrigatório para MUST e MUST NOT)').fill(rule.subject);
  await form.getByLabel('Regra', { exact: true }).fill(rule.statement);
  await form.getByRole('button', { name: 'Propor regra' }).click();
  await expect(form.getByText('Regra proposta. Aguarda ativação.')).toBeVisible();
}

function ruleCard(page: Page, statement: string) {
  return page
    .getByRole('region', { name: 'Todas as regras' })
    .getByRole('listitem')
    .filter({ hasText: statement });
}

test.describe('client brain', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('admin reads the seeded Brain, and a rule conflict is detected and resolved by a person', async ({
    page,
  }) => {
    await login(page, SEED.users.admin);
    await page.goto(`/w/${SEED.workspaces.jansen}/clients/${SEED.clients.a}`);
    await page.getByRole('link', { name: 'Abrir Client Brain' }).click();
    await expect(
      page.getByRole('heading', { level: 1, name: 'Client Brain: Cliente Demo A' }),
    ).toBeVisible();
    await expect(page.getByLabel('Negócio')).toHaveValue(
      'Clínica odontológica familiar com três unidades.',
    );
    await expect(page.getByText('Famílias com crianças')).toBeVisible();

    await page
      .getByRole('navigation', { name: 'Seções do Client Brain' })
      .getByRole('link', { name: 'Regras' })
      .click();
    await expect(page).toHaveURL(`${BRAIN}/rules`);

    const subject = unique('assunto').replace(/[^a-z0-9-]/g, '-');
    const must = unique('Sempre use hashtags');
    const mustNot = unique('Nunca use hashtags');

    await proposeRule(page, { type: 'MUST', subject, statement: must });
    await ruleCard(page, must).getByRole('button', { name: 'Ativar' }).click();
    await expect(ruleCard(page, must).getByText('Regra ativada.')).toBeVisible();

    await proposeRule(page, { type: 'MUST_NOT', subject, statement: mustNot });
    await ruleCard(page, mustNot).getByRole('button', { name: 'Ativar' }).click();
    await expect(ruleCard(page, mustNot).getByText(/entrou em conflito/)).toBeVisible();

    const banner = page.getByRole('alert').filter({ hasText: 'Conflito de regras' });
    await expect(banner).toContainText(subject);
    const effective = page.getByRole('list', { name: 'Regras efetivas' });
    await expect(effective.getByText(must)).toHaveCount(0);

    await page
      .getByRole('region', { name: 'Conflitos a resolver' })
      .getByRole('listitem')
      .filter({ hasText: mustNot })
      .getByRole('button', { name: 'Rejeitar este lado' })
      .click();
    await expect(page.getByRole('alert').filter({ hasText: subject })).toHaveCount(0);
    await expect(page.getByRole('list', { name: 'Regras efetivas' }).getByText(must)).toBeVisible();
    await expect(ruleCard(page, mustNot).getByText('Rejeitada')).toBeVisible();
  });

  test('knowledge enters as proposed and only an approver of knowledge makes it active', async ({
    page,
  }) => {
    const statement = unique('Atende convênios odontológicos');

    await login(page, SEED.users.strategist);
    await page.goto(`${BRAIN}/knowledge`);
    const form = page.getByRole('region', { name: 'Propor conhecimento' });
    await form.getByLabel('Tipo').selectOption('fact');
    await form.getByLabel('Fonte').selectOption(SEEDED.trustedSource);
    await form.getByLabel('Enunciado').fill(statement);
    await form.getByRole('button', { name: 'Propor' }).click();
    await expect(form.getByText('Proposto. Aguarda aprovação.')).toBeVisible();

    const card = page.getByRole('listitem').filter({ hasText: statement });
    await expect(card.getByText('Proposto', { exact: true })).toBeVisible();
    // A strategist proposes but does not approve (knowledge.approve is admin-only by default).
    await expect(card.getByRole('button', { name: 'Aprovar' })).toHaveCount(0);
    await logout(page);

    await login(page, SEED.users.admin);
    await page.goto(`${BRAIN}/knowledge`);
    const adminCard = page.getByRole('listitem').filter({ hasText: statement });
    await adminCard.getByRole('button', { name: 'Aprovar' }).click();
    await expect(adminCard.getByText('Ativo', { exact: true })).toBeVisible();
  });

  test('client-side users and contributors without a grant never reach the Brain', async ({
    page,
  }) => {
    await login(page, SEED.users.approverA);
    await expectNotFound(page, BRAIN);
    await expectNotFound(page, `${BRAIN}/rules`);
    await logout(page);

    await login(page, SEED.users.contributor);
    await expectNotFound(page, `${BRAIN}/knowledge`);
  });

  test('the database boundary holds for raw API calls', async () => {
    const config = requireSupabase();

    // Client Approver: the Brain is internal-only, and it cannot activate rules (docs/11).
    const approver = await apiAs(config, SEED.users.approverA);
    expect((await approver.select('rules', 'id')).data).toEqual([]);
    expect((await approver.select('facts', 'id')).data).toEqual([]);
    expect((await approver.rpc('activate_rule', { p_rule_id: SEEDED.proposedRule })).code).toBe(
      'P0002',
    );
    expect((await approver.rpc('effective_rules', { p_client_id: SEED.clients.a })).data).toEqual(
      [],
    );

    // Strategist: reads the Brain, proposes, but holds neither rule.activate nor knowledge.approve.
    const strategist = await apiAs(config, SEED.users.strategist);
    expect((await strategist.rpc('activate_rule', { p_rule_id: SEEDED.proposedRule })).code).toBe(
      '42501',
    );
    expect(
      (await strategist.rpc('approve_knowledge', { p_kind: 'fact', p_id: SEEDED.proposedFact }))
        .code,
    ).toBe('42501');

    // Nobody changes state directly, not even an admin.
    const admin = await apiAs(config, SEED.users.admin);
    const direct = await admin.update('rules', { status: 'active' }, SEEDED.proposedRule);
    expect(direct.code).toBe('42501');

    // Another agency's admin sees nothing of client A.
    const other = await apiAs(config, SEED.users.otherAdmin);
    expect((await other.rpc('effective_rules', { p_client_id: SEED.clients.a })).data).toEqual([]);
    expect(
      (await other.rpc('approve_knowledge', { p_kind: 'fact', p_id: SEEDED.proposedFact })).code,
    ).toBe('P0002');
  });
});
