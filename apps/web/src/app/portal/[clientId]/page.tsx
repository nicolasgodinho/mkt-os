import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, PageHeader, StatusBadge } from '@jmos/ui';
import { PortalEvent } from '@/components/calendar/portal-event';
import { upcomingRange } from '@/lib/calendar/model';
import { calendarEvents } from '@/lib/calendar/queries';
import { needsAttention } from '@/lib/collab/model';
import { portalApprovals } from '@/lib/collab/queries';
import { portalAreasFor } from '@/lib/identity/capabilities';
import { formatDateTime } from '@/lib/jobs/model';
import { requirePortalContext } from '@/lib/portal/context';

export const metadata: Metadata = { title: 'Portal' };

const ROLE_LABELS = {
  client_admin: 'Administrador do cliente',
  approver: 'Aprovador',
  collaborator: 'Colaborador',
  viewer: 'Visualizador',
} as const;

/**
 * Portal home for one client (docs/07 §14): first what needs the client now, then the areas.
 * Requires an active client-side membership for exactly this client: any other id renders the
 * same 404.
 */
export default async function PortalClientPage({
  params,
}: {
  params: Promise<{ clientId: string }>;
}) {
  const { clientId } = await params;
  const { client, membership, capabilities } = await requirePortalContext(
    clientId,
    `/portal/${clientId}`,
  );
  const areas = portalAreasFor(capabilities);
  const canDecide = capabilities.includes('approval.decide');
  const pending = canDecide ? needsAttention(await portalApprovals(client.id)) : [];
  const canView = capabilities.includes('client.view');
  const nextDays = upcomingRange(7);
  const nextWeek = canView ? await calendarEvents(nextDays.from, nextDays.to, client.id) : [];
  const base = `/portal/${client.id}`;

  return (
    <>
      <PageHeader title={client.name} description="O que precisa da sua atenção agora." />
      <p className="mb-4 text-sm">
        Seu perfil: <StatusBadge tone="info">{ROLE_LABELS[membership.role]}</StatusBadge>
      </p>

      {canDecide ? (
        <section aria-labelledby="needs-you" className="mb-6">
          <h2 id="needs-you" className="mb-2 text-sm font-medium">
            Precisa de você
          </h2>
          {pending.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nada aguardando sua aprovação agora.</p>
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Aguardando sua aprovação">
              {pending.map((row) => (
                <li key={row.request_id}>
                  <Link
                    href={`${base}/approvals/${row.request_id}`}
                    className="block rounded-lg border bg-surface px-4 py-3"
                  >
                    <span className="block font-medium">{row.content_title}</span>
                    <span className="block text-xs text-muted-foreground">
                      {row.channel} · {row.format}
                      {row.due_at ? ` · aprovar até ${formatDateTime(row.due_at)}` : ''}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}

      {canView ? (
        <section aria-labelledby="next-days" className="mb-6">
          <h2 id="next-days" className="mb-2 text-sm font-medium">
            Próximos 7 dias
          </h2>
          {nextWeek.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nada agendado para os próximos dias.</p>
          ) : (
            <ul className="flex flex-col gap-2" aria-label="Próximos 7 dias">
              {nextWeek.map((event) => (
                <PortalEvent key={`${event.event_type}-${event.entity_id}`} event={event} />
              ))}
            </ul>
          )}
        </section>
      ) : null}

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
                {area.key === 'requests' ? (
                  <p className="font-medium">{area.label}</p>
                ) : (
                  <Link
                    href={area.key === 'approvals' ? `${base}/approvals` : `${base}/calendar`}
                    className="font-medium text-primary"
                  >
                    {area.label}
                  </Link>
                )}
                <p className="text-sm text-muted-foreground">{area.description}</p>
                {area.key === 'requests' ? (
                  <p className="mt-1 text-xs text-muted-foreground">Disponível em breve</p>
                ) : null}
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
