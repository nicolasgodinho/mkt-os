import { expect, test } from '@playwright/test';
import { CAPABILITIES } from '../../apps/web/src/lib/identity/capabilities';
import { anonymousApi, apiAs, requireSupabase, SEED } from './support/supabase';

/**
 * The real authorization boundary: raw HTTP to PostgREST with the same public key and user access
 * token a browser holds. Route protection is irrelevant here, so these calls prove what an attacker
 * with a valid account could actually do.
 */
test.describe('database API boundary (Auth + PostgREST + RLS)', () => {
  test('a client approver cannot perform internal operations or reach other clients', async () => {
    const api = await apiAs(requireSupabase(), SEED.users.approverA);

    const clients = await api.select('clients', 'id');
    expect(clients.code).toBeUndefined();
    expect(clients.data).toEqual([{ id: SEED.clients.a }]);

    const ownClient = await api.rpc('update_client', { p_client_id: SEED.clients.a, p_name: 'x' });
    expect(ownClient.code).toBe('42501');

    const sibling = await api.rpc('update_client', { p_client_id: SEED.clients.b, p_name: 'x' });
    const random = await api.rpc('update_client', { p_client_id: SEED.randomId, p_name: 'x' });
    expect(sibling.code).toBe('P0002');
    // Identical answers: a guessed id reveals nothing about existence.
    expect([sibling.status, sibling.code, sibling.message]).toEqual([
      random.status,
      random.code,
      random.message,
    ]);

    const internal = await api.rpc('create_client', {
      p_workspace_id: SEED.workspaceIds.jansen,
      p_name: 'Rogue',
      p_slug: 'rogue',
    });
    expect(internal.code).toBe('P0002');

    const jobs = await api.select('jobs', 'id');
    expect(jobs.data).toEqual([]);
  });

  test('a viewer cannot write', async () => {
    const api = await apiAs(requireSupabase(), SEED.users.viewerB);
    const update = await api.rpc('update_client', { p_client_id: SEED.clients.b, p_name: 'x' });
    expect(update.code).toBe('42501');
    const direct = await api.update('clients', { name: 'x' }, SEED.clients.b);
    expect(direct.code).toBe('42501');
  });

  test('an admin cannot reach another workspace, whatever the payload says', async () => {
    const api = await apiAs(requireSupabase(), SEED.users.admin);
    const other = await api.rpc('update_client', { p_client_id: SEED.clients.c, p_name: 'x' });
    expect(other.code).toBe('P0002');
    const member = await api.rpc('set_client_member', {
      p_client_id: SEED.clients.c,
      p_user_id: '00000000-0000-4000-8000-000000000001',
      p_role: 'client_admin',
    });
    expect(member.code).toBe('P0002');
  });

  test('the web capability list matches the database contract', async () => {
    const api = await apiAs(requireSupabase(), SEED.users.admin);
    const result = await api.rpc('workspace_capabilities', {
      p_workspace_id: SEED.workspaceIds.jansen,
    });
    expect(result.code).toBeUndefined();
    expect(Array.isArray(result.data)).toBe(true);
    expect([...(result.data as string[])].sort()).toEqual([...CAPABILITIES].sort());
  });

  test('without a session nothing is readable or callable', async () => {
    const api = anonymousApi(requireSupabase());
    const clients = await api.select('clients', 'id');
    expect(clients.code).toBe('42501');
    const rpc = await api.rpc('workspace_capabilities', {
      p_workspace_id: SEED.workspaceIds.jansen,
    });
    expect(rpc.code).toBe('42501');
  });
});
