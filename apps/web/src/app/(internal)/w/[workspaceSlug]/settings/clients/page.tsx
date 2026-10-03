import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { archiveClient, createClient, renameClient } from '@/lib/admin/actions';
import { requireWorkspaceAdmin } from '@/lib/admin/context';
import { listWorkspaceClients } from '@/lib/identity/queries';

export const metadata: Metadata = { title: 'Clientes do workspace' };

/** Clients of the workspace: create, rename, archive, and open their portal access (Increment 9). */
export default async function ClientSettingsPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string }>;
}) {
  const { workspaceSlug } = await params;
  const { workspace } = await requireWorkspaceAdmin(
    workspaceSlug,
    'client.manage',
    `/w/${workspaceSlug}/settings/clients`,
  );
  const clients = await listWorkspaceClients(workspace.id);
  const scope = { workspaceSlug: workspace.slug, workspaceId: workspace.id };

  return (
    <div className="flex flex-col gap-6">
      <section aria-labelledby="new-client" className="rounded-lg border bg-surface p-4">
        <h2 id="new-client" className="text-sm font-medium">
          Novo cliente
        </h2>
        <ActionForm
          action={createClient}
          hidden={scope}
          buttons={[{ label: 'Criar cliente' }]}
          pendingLabel="Criando…"
          resetOnSuccess
          className="mt-3 max-w-xl"
        >
          <TextField
            id="client-name"
            name="name"
            label="Nome do cliente"
            maxLength={200}
            required
          />
          <TextField
            id="client-slug"
            name="slug"
            label="Identificador (letras minúsculas, números e hífens)"
            placeholder="clinica-sorriso"
            pattern="[a-z0-9]+(-[a-z0-9]+)*"
            maxLength={60}
            required
          />
        </ActionForm>
      </section>

      <section aria-labelledby="clients">
        <h2 id="clients" className="mb-2 text-sm font-medium">
          Clientes
        </h2>
        {clients.length === 0 ? (
          <EmptyState title="Nenhum cliente ainda" description="Crie o primeiro cliente acima." />
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Clientes do workspace">
            {clients.map((client) => {
              const hidden = { ...scope, clientId: client.id };
              return (
                <li key={client.id} className="rounded-lg border bg-surface p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium">{client.name}</span>
                    <span className="text-xs text-muted-foreground">{client.slug}</span>
                    {client.status === 'archived' ? (
                      <StatusBadge tone="neutral">Arquivado</StatusBadge>
                    ) : (
                      <Link
                        href={`/w/${workspace.slug}/clients/${client.id}/access`}
                        className="text-xs text-primary"
                      >
                        Acesso do cliente ao portal
                      </Link>
                    )}
                  </div>
                  {client.status === 'active' ? (
                    <details className="mt-2">
                      <summary className="cursor-pointer text-xs text-primary">Editar</summary>
                      <ActionForm
                        action={renameClient}
                        hidden={hidden}
                        buttons={[
                          { label: 'Salvar nome', ariaLabel: `Salvar nome de ${client.name}` },
                        ]}
                        variant="inline"
                        className="mt-2"
                      >
                        <TextField
                          id={`rename-${client.id}`}
                          name="name"
                          label="Nome"
                          defaultValue={client.name}
                          maxLength={200}
                          required
                        />
                      </ActionForm>
                      <ActionForm
                        action={archiveClient}
                        hidden={hidden}
                        buttons={[
                          {
                            label: 'Arquivar cliente',
                            ariaLabel: `Arquivar ${client.name}`,
                            variant: 'secondary',
                          },
                        ]}
                        variant="inline"
                        className="mt-2"
                      />
                    </details>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
