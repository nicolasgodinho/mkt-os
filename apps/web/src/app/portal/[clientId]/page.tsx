import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { EmptyState, PageHeader, StatusBadge } from '@jmos/ui';
import { requireSessionUser } from '@/lib/auth/session';
import { portalAreasFor } from '@/lib/identity/capabilities';
import { isUuid } from '@/lib/identity/routing';
import { getClient, getClientCapabilities, listMyPortalMemberships } from '@/lib/identity/queries';

export const metadata: Metadata = { title: 'Portal' };

const ROLE_LABELS = {
  client_admin: 'Administrador do cliente',
  approver: 'Aprovador',
  collaborator: 'Colaborador',
  viewer: 'Visualizador',
} as const;

/**
 * Portal home for one client (docs/07 §14, foundation part). Requires an active client-side
 * membership for exactly this client: any other id renders the same 404.
 */
export default async function PortalClientPage({
  params,
}: {
  params: Promise<{ clientId: string }>;
}) {
  const { clientId } = await params;
  if (!isUuid(clientId)) notFound();
  const user = await requireSessionUser(`/portal/${clientId}`);
  const membership = (await listMyPortalMemberships(user.id)).find((m) => m.client_id === clientId);
  if (membership === undefined) notFound();
  const client = await getClient(clientId);
  if (client === null) notFound();
  const areas = portalAreasFor(await getClientCapabilities(clientId));

  return (
    <>
      <PageHeader title={client.name} description="O que precisa da sua atenção agora." />
      <p className="mb-4 text-sm">
        Seu perfil: <StatusBadge tone="info">{ROLE_LABELS[membership.role]}</StatusBadge>
      </p>
      <section aria-labelledby="areas">
        <h2 id="areas" className="mb-2 text-sm font-medium">
          Áreas disponíveis para você
        </h2>
        {areas.length === 0 ? (
          <EmptyState title="Nenhuma área disponível" />
        ) : (
          <ul className="flex flex-col gap-2" data-testid="portal-areas">
            {areas.map((area) => (
              <li key={area.key} className="rounded-lg border bg-surface px-4 py-3">
                <p className="font-medium">{area.label}</p>
                <p className="text-sm text-muted-foreground">{area.description}</p>
                <p className="mt-1 text-xs text-muted-foreground">Disponível em breve</p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
