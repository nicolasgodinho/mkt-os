import type { Metadata } from 'next';
import { EmptyState, SelectField, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { formatDate } from '@/lib/brain/model';
import { capabilityFlags } from '@/lib/content/access';
import { createInitiative, setInitiativeStatus } from '@/lib/content/actions';
import {
  INITIATIVE_KIND_LABELS,
  INITIATIVE_KINDS,
  INITIATIVE_STATUS,
  nextInitiativeStatuses,
} from '@/lib/content/model';
import { listInitiatives } from '@/lib/content/queries';

export const metadata: Metadata = { title: 'Iniciativas' };

/** Initiatives (docs/02, docs/04): campaigns, always-on, launches and activations. */
export default async function InitiativesPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { workspace, client } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/content/initiatives`,
  );
  const can = await capabilityFlags(workspace.id);
  const initiatives = await listInitiatives(client.id);
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };

  return (
    <div className="flex flex-col gap-6">
      {initiatives.length === 0 ? (
        <EmptyState
          title="Nenhuma iniciativa"
          description="Agrupe pautas em campanhas, lançamentos ou ações contínuas."
        />
      ) : (
        <ul className="flex flex-col gap-2" aria-label="Iniciativas">
          {initiatives.map((initiative) => (
            <li key={initiative.id} className="rounded-lg border bg-surface p-3">
              <div className="flex flex-wrap items-center gap-1.5">
                <span className="text-sm font-medium">{initiative.name}</span>
                <StatusBadge tone={INITIATIVE_STATUS[initiative.status].tone}>
                  {INITIATIVE_STATUS[initiative.status].label}
                </StatusBadge>
                <StatusBadge tone="neutral">{INITIATIVE_KIND_LABELS[initiative.kind]}</StatusBadge>
              </div>
              {initiative.start_at || initiative.end_at ? (
                <p className="mt-1 text-xs text-muted-foreground">
                  {formatDate(initiative.start_at) ?? '…'} até{' '}
                  {formatDate(initiative.end_at) ?? '…'}
                </p>
              ) : null}
              {can.strategy ? (
                <ActionForm
                  action={setInitiativeStatus}
                  hidden={{ ...scope, id: initiative.id }}
                  buttons={nextInitiativeStatuses(initiative).map((status) => ({
                    label: INITIATIVE_STATUS[status].label,
                    value: status,
                    variant: 'secondary' as const,
                    ariaLabel: `Mudar ${initiative.name} para ${INITIATIVE_STATUS[status].label}`,
                  }))}
                  pendingLabel="Enviando…"
                  variant="inline"
                  className="mt-2"
                />
              ) : null}
            </li>
          ))}
        </ul>
      )}
      {can.strategy ? (
        <section
          aria-labelledby="section-new-initiative"
          className="rounded-lg border bg-surface p-4"
        >
          <h2 id="section-new-initiative" className="text-sm font-medium">
            Nova iniciativa
          </h2>
          <ActionForm
            action={createInitiative}
            hidden={scope}
            buttons={[{ label: 'Criar iniciativa' }]}
            resetOnSuccess
            className="mt-3 max-w-2xl"
          >
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField id="initiative-name" name="name" label="Nome" required maxLength={200} />
              <SelectField
                id="initiative-kind"
                name="kind"
                label="Tipo"
                options={INITIATIVE_KINDS.map((kind) => ({
                  value: kind,
                  label: INITIATIVE_KIND_LABELS[kind],
                }))}
              />
              <TextField
                id="initiative-start"
                name="startAt"
                type="date"
                label="Início (opcional)"
              />
              <TextField id="initiative-end" name="endAt" type="date" label="Fim (opcional)" />
            </div>
          </ActionForm>
        </section>
      ) : null}
    </div>
  );
}
