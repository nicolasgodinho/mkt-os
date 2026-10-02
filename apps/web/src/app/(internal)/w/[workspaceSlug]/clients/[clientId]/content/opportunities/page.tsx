import type { Metadata } from 'next';
import { EmptyState, SelectField, StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { ActionForm, type ActionFormButton } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { formatDate } from '@/lib/brain/model';
import { listSources } from '@/lib/brain/queries';
import { capabilityFlags } from '@/lib/content/access';
import { createOpportunity, reviewOpportunity } from '@/lib/content/actions';
import { OPPORTUNITY_STATUS } from '@/lib/content/model';
import { listOpportunities } from '@/lib/content/queries';

export const metadata: Metadata = { title: 'Oportunidades' };

/** Opportunity Inbox (docs/07 §6): a reason to act, not yet an editorial commitment. */
export default async function OpportunitiesPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { workspace, client } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/content/opportunities`,
  );
  const can = await capabilityFlags(workspace.id);
  const [opportunities, sources] = await Promise.all([
    listOpportunities(client.id),
    listSources(client.id),
  ]);
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };
  const sourceTitle = new Map(sources.map((source) => [source.id, source.title]));

  return (
    <div className="flex flex-col gap-6">
      {opportunities.length === 0 ? (
        <EmptyState
          title="Nenhuma oportunidade"
          description="Registre sinais que justificam agir: datas, tendências, pedidos e aprendizados."
        />
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Oportunidades">
          {opportunities.map((opportunity) => {
            const open = ['detected', 'reviewed', 'watching'].includes(opportunity.status);
            const buttons: ActionFormButton[] = open
              ? [
                  {
                    label: 'Converter em pauta',
                    value: 'convert',
                    ariaLabel: `Converter em pauta: ${opportunity.title}`,
                  },
                  ...(opportunity.status === 'watching'
                    ? []
                    : [
                        {
                          label: 'Acompanhar',
                          value: 'watch',
                          variant: 'secondary' as const,
                          ariaLabel: `Acompanhar: ${opportunity.title}`,
                        },
                      ]),
                  {
                    label: 'Descartar',
                    value: 'dismiss',
                    variant: 'ghost' as const,
                    ariaLabel: `Descartar: ${opportunity.title}`,
                  },
                ]
              : [];
            return (
              <li key={opportunity.id} className="rounded-lg border bg-surface p-3">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="text-sm font-medium">{opportunity.title}</span>
                  <StatusBadge tone={OPPORTUNITY_STATUS[opportunity.status].tone}>
                    {OPPORTUNITY_STATUS[opportunity.status].label}
                  </StatusBadge>
                  <StatusBadge tone="neutral">{opportunity.type}</StatusBadge>
                </div>
                <p className="mt-1 text-sm text-muted-foreground">{opportunity.reason}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {opportunity.confidence !== null
                    ? `Confiança ${Math.round(opportunity.confidence * 100).toString()}% · `
                    : ''}
                  {opportunity.expires_at
                    ? `Válida até ${formatDate(opportunity.expires_at) ?? ''} · `
                    : ''}
                  Evidência:{' '}
                  {opportunity.evidence_refs.length === 0
                    ? 'nenhuma'
                    : opportunity.evidence_refs
                        .map((id) => sourceTitle.get(id) ?? 'fonte')
                        .join(', ')}
                </p>
                {can.strategy ? (
                  <ActionForm
                    action={reviewOpportunity}
                    hidden={{ ...scope, id: opportunity.id }}
                    buttons={buttons}
                    pendingLabel="Enviando…"
                    variant="inline"
                    className="mt-2"
                  />
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      {can.strategy ? (
        <section
          aria-labelledby="section-new-opportunity"
          className="rounded-lg border bg-surface p-4"
        >
          <h2 id="section-new-opportunity" className="text-sm font-medium">
            Nova oportunidade
          </h2>
          <ActionForm
            action={createOpportunity}
            hidden={scope}
            buttons={[{ label: 'Registrar oportunidade' }]}
            resetOnSuccess
            className="mt-3 max-w-2xl"
          >
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField id="opp-title" name="title" label="Título" required maxLength={300} />
              <TextField
                id="opp-type"
                name="type"
                label="Tipo (ex.: sazonal, tendencia)"
                required
                maxLength={40}
              />
            </div>
            <TextAreaField
              id="opp-reason"
              name="reason"
              label="Por que importa"
              required
              maxLength={4000}
            />
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField
                id="opp-expires"
                name="expiresAt"
                type="date"
                label="Vale até (opcional)"
              />
              <SelectField
                id="opp-source"
                name="sourceId"
                label="Evidência (opcional)"
                options={[
                  { value: '', label: 'Nenhuma' },
                  ...sources.map((source) => ({ value: source.id, label: source.title })),
                ]}
              />
            </div>
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
