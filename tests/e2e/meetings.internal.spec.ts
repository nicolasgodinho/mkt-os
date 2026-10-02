import { expect, test } from '@playwright/test';
import { apiAs, expectNotFound, login, logout, requireSupabase, SEED } from './support/supabase';

// Meeting intelligence (Increment 4) with real sessions. Skipped locally without the stack.
const MEETINGS = `/w/${SEED.workspaces.jansen}/clients/${SEED.clients.a}/meetings`;
const SEEDED_MEETING = '31000000-0000-4000-8000-000000000001';
const SEEDED_TASK = '31000000-0000-4000-8000-0000000000b5';

function unique(label: string): string {
  return `${label} e2e-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

test.describe('meeting intelligence', () => {
  test.beforeEach(() => {
    requireSupabase();
  });

  test('a strategist registers a meeting, pastes the transcript and queues the extraction', async ({
    page,
  }) => {
    const title = unique('Reunião de alinhamento');
    await login(page, SEED.users.strategist);
    await page.goto(MEETINGS);
    const form = page.getByRole('region', { name: 'Nova reunião' });
    await form.getByLabel('Título').fill(title);
    await form.getByLabel('Início').fill('2026-10-02T10:00');
    await form.getByLabel('Participantes (um por linha)').fill('Ana\nBruno');
    await form.getByRole('button', { name: 'Criar reunião' }).click();
    await expect(form.getByText('Reunião criada.')).toBeVisible();

    await page.getByRole('link', { name: title }).click();
    await expect(page.getByRole('heading', { level: 1, name: title })).toBeVisible();
    await expect(page.getByText('Sem transcrição')).toBeVisible();

    const transcript = page.getByRole('region', { name: 'Transcrição' });
    await transcript.getByLabel('Texto da transcrição').fill('Ana: queremos falar com famílias.');
    await transcript.getByRole('button', { name: 'Salvar transcrição' }).click();
    await expect(transcript.getByText(/Transcrição salva \(revisão 1\)/)).toBeVisible();

    const processing = page.getByRole('region', { name: 'Processamento' });
    await processing.getByRole('button', { name: 'Extrair conhecimento' }).click();
    await expect(processing.getByText(/Enviado para a fila do AI Worker/)).toBeVisible();
    await page.reload();
    await expect(
      page.getByRole('list', { name: 'Jobs desta reunião' }).getByText('meeting.extract'),
    ).toBeVisible();
  });

  test('accepting a proposal sends it to the Client Brain as PROPOSED; approval stays there', async ({
    page,
  }) => {
    await login(page, SEED.users.strategist);
    await page.goto(`${MEETINGS}/${SEEDED_MEETING}`);
    const facts = page.getByRole('list', { name: 'Fato' });
    const fact = facts.getByRole('listitem').first();
    const edited = unique('A clínica abre aos domingos desde novembro.');

    await fact.getByText('Editar antes de aceitar').click();
    await fact.getByLabel('Enunciado').fill(edited);
    await fact.getByRole('button', { name: /^Aceitar:/ }).click();
    await expect(fact.getByText(/Enviado ao Client Brain como proposta/)).toBeVisible();
    await expect(fact.getByText('Aceito no Client Brain')).toBeVisible();

    await fact.getByRole('link', { name: 'Ver no Client Brain' }).click();
    const card = page.getByRole('listitem').filter({ hasText: edited });
    await expect(card.getByText('Proposto', { exact: true })).toBeVisible();
    // The strategist cannot approve (knowledge.approve): only proposed knowledge was created.
    await expect(card.getByRole('button', { name: /^Aprovar/ })).toHaveCount(0);
    await logout(page);
  });

  test('client users never reach meetings, and tasks cannot be promoted', async ({ page }) => {
    await login(page, SEED.users.approverA);
    await expectNotFound(page, MEETINGS);
    await expectNotFound(page, `${MEETINGS}/${SEEDED_MEETING}`);

    const config = requireSupabase();
    const approver = await apiAs(config, SEED.users.approverA);
    expect((await approver.select('meetings', 'id')).data).toEqual([]);
    expect((await approver.select('meeting_proposals', 'id')).data).toEqual([]);

    const strategist = await apiAs(config, SEED.users.strategist);
    const task = await strategist.rpc('accept_meeting_proposal', { p_proposal_id: SEEDED_TASK });
    expect(task.code).toBe('22023');
    const forged = await strategist.update(
      'meeting_proposals',
      { status: 'accepted' },
      SEEDED_TASK,
    );
    expect(forged.code).toBe('42501');
  });
});
