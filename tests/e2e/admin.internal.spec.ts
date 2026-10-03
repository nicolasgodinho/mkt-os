import { expect, test, type Browser, type Page } from '@playwright/test';
import { expectNotFound, login, requireSupabase, SEED } from './support/supabase';

// Administration and invitations (Increment 9) with the real Supabase Auth, including the
// invite-only signup hook. Skipped locally without the stack. Every run invites fresh e-mails.
const SETTINGS = `/w/${SEED.workspaces.jansen}/settings`;
const ACCESS_A = `/w/${SEED.workspaces.jansen}/clients/${SEED.clients.a}/access`;
const PASSWORD = 'Convite-e2e-2026!';

function unique(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

/** The invitation link shown once to the inviter. */
async function invitationLink(page: Page): Promise<string> {
  const message = page.getByText(/Convite criado\. Envie este link/);
  await expect(message).toBeVisible();
  const match = /\/convite\/[0-9a-f]{64}/.exec((await message.textContent()) ?? '');
  expect(match).not.toBeNull();
  return match?.[0] ?? '';
}

/** A new person opens the link in a fresh browser and creates the account. */
async function signUpThroughLink(browser: Browser, link: string, email: string): Promise<Page> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(link);
  const form = page.getByRole('region', { name: 'Criar conta' });
  await form.getByLabel('Seu nome').fill('Pessoa Convidada');
  await form.getByLabel('E-mail').fill(email);
  await form.getByLabel('Senha (mínimo 10 caracteres)').fill(PASSWORD);
  await form.getByRole('button', { name: 'Criar conta e aceitar' }).click();
  return page;
}

test.describe('administration and invitations', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('an admin invites a team member, who signs up through the link and joins', async ({
    page,
    browser,
  }) => {
    const email = `${unique('equipe')}@convite.test`;
    await login(page, SEED.users.admin);
    await page.goto(SETTINGS);
    const invite = page.getByRole('region', { name: 'Convidar para a equipe' });
    await invite.getByLabel('E-mail').fill(email);
    await invite.getByLabel('Papel').selectOption('creative');
    await invite.getByRole('button', { name: 'Criar convite' }).click();
    const link = await invitationLink(page);

    const invited = await signUpThroughLink(browser, link, email);
    await expect(invited).toHaveURL(new RegExp(`/w/${SEED.workspaces.jansen}$`));
    await expect(invited.getByRole('navigation', { name: 'Navegação principal' })).toBeVisible();
    await invited.context().close();

    await page.reload();
    const member = page
      .getByRole('list', { name: 'Membros da equipe' })
      .getByRole('listitem')
      .filter({ hasText: email });
    await expect(member.getByText('Ativo')).toBeVisible();
    await expect(member.getByText('Criação')).toBeVisible();
  });

  test('a client approver is invited to the portal and lands on the client', async ({
    page,
    browser,
  }) => {
    const email = `${unique('aprovador')}@cliente.test`;
    await login(page, SEED.users.admin);
    await page.goto(ACCESS_A);
    const invite = page.getByRole('region', { name: 'Convidar pessoa do cliente' });
    await invite.getByLabel('E-mail').fill(email);
    await invite.getByLabel('Papel no portal').selectOption('approver');
    await invite.getByRole('button', { name: 'Criar convite' }).click();
    const link = await invitationLink(page);

    const invited = await signUpThroughLink(browser, link, email);
    await expect(invited).toHaveURL(new RegExp(`/portal/${SEED.clients.a}$`));
    await expect(invited.getByRole('heading', { level: 1, name: 'Cliente Demo A' })).toBeVisible();
    await invited.context().close();
  });

  test('without an invitation nobody can sign up, and a token for another e-mail grants nothing', async ({
    page,
    browser,
  }) => {
    await login(page, SEED.users.admin);
    await page.goto(SETTINGS);
    const invite = page.getByRole('region', { name: 'Convidar para a equipe' });
    await invite.getByLabel('E-mail').fill(`${unique('certa')}@convite.test`);
    await invite.getByRole('button', { name: 'Criar convite' }).click();
    const link = await invitationLink(page);

    // The link with an e-mail that was never invited: the signup hook refuses the account.
    const intruder = await signUpThroughLink(browser, link, `${unique('intruso')}@x.test`);
    await expect(
      intruder.getByText(/Não foi possível criar a conta com este e-mail/),
    ).toBeVisible();
    await intruder.context().close();
  });

  test('clients are created and archived; settings are for managers only', async ({ page }) => {
    const slug = unique('cliente-e2e');
    await login(page, SEED.users.admin);
    await page.goto(`${SETTINGS}/clients`);
    const create = page.getByRole('region', { name: 'Novo cliente' });
    await create.getByLabel('Nome do cliente').fill(`Cliente ${slug}`);
    await create.getByLabel(/Identificador/).fill(slug);
    await create.getByRole('button', { name: 'Criar cliente' }).click();
    await expect(create.getByText('Cliente criado.')).toBeVisible();

    const row = page
      .getByRole('list', { name: 'Clientes do workspace' })
      .getByRole('listitem')
      .filter({ hasText: slug });
    await row.getByText('Editar').click();
    await row.getByRole('button', { name: `Arquivar Cliente ${slug}` }).click();
    await expect(row.getByText('Arquivado')).toBeVisible();

    await page.context().clearCookies();
    await login(page, SEED.users.strategist);
    await expectNotFound(page, SETTINGS);
    await expectNotFound(page, ACCESS_A);
  });
});
