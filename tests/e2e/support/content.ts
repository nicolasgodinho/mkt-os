import { expect } from '@playwright/test';
import { apiAs, requireSupabase, SEED, type Api } from './supabase';

// Content fixtures created through the database API (Increments 5–7), so E2E runs never mutate
// the seed and can be repeated.
const A_PAUTA = '32000000-0000-4000-8000-000000000001';

export function unique(label: string): string {
  return `${label} e2e-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

/** Calls the API and fails the test on any database error. */
export async function ok(api: Api, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const result = await api.rpc(fn, args);
  expect(result.code, `${fn}: ${result.message ?? ''}`).toBeUndefined();
  return result.data;
}

/** Content approved internally and sent to Cliente Demo A; returns its ids. */
export async function sendToClient(admin: Api, title: string) {
  const contentId = (await ok(admin, 'create_content', {
    p_pauta_id: A_PAUTA,
    p_channel: 'instagram',
    p_format: 'post',
    p_title: title,
  })) as string;
  await ok(admin, 'save_content_payload', {
    p_content_id: contentId,
    p_payload: {
      headline: 'Sorriso de família',
      body: 'Prevenção começa cedo. Traga a família para uma avaliação.',
      cta: 'Agende pelo WhatsApp',
    },
  });
  const revisionId = (await ok(admin, 'submit_for_internal_review', {
    p_content_id: contentId,
  })) as string;
  const rules = (await ok(admin, 'revision_validation', { p_revision_id: revisionId })) as {
    rule_id: string;
  }[];
  for (const rule of rules) {
    await ok(admin, 'record_rule_check', {
      p_revision_id: revisionId,
      p_rule_id: rule.rule_id,
      p_result: 'pass',
    });
  }
  await ok(admin, 'complete_internal_review', { p_revision_id: revisionId, p_decision: 'approve' });
  const requestId = (await ok(admin, 'request_client_approval', {
    p_revision_id: revisionId,
  })) as string;
  return { contentId, requestId };
}

/** Content approved by the team and by Cliente Demo A's approver; returns its ids. */
export async function clientApproved(admin: Api, title: string) {
  const sent = await sendToClient(admin, title);
  const approver = await apiAs(requireSupabase(), SEED.users.approverA);
  await ok(approver, 'decide_approval', { p_request_id: sent.requestId, p_decision: 'approve' });
  return sent;
}
