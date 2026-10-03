import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader, StatusBadge } from '@jmos/ui';
import { CAPABILITY_LABELS } from '@/lib/identity/capabilities';
import { requireSessionUser } from '@/lib/auth/session';
import { getClient, getClientCapabilities, getWorkspaceBySlug } from '@/lib/identity/queries';

export const metadata: Metadata = { title: 'Cliente' };

/**
 * Client context (docs/07 §3, identity/status part). An id the member cannot access — another
 * client, another workspace or nothing at all — renders the same 404.
 */
export default async function ClientPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  // Pages render in parallel with layouts, so every page checks the session itself.
  await requireSessionUser(`/w/${workspaceSlug}/clients/${clientId}`);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  const client = await getClient(clientId);
  if (client?.workspace_id !== workspace.id) notFound();
  const capabilities = await getClientCapabilities(client.id);

  return (
    <>
      <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
        <Link href={`/w/${workspace.slug}/clients`} className="hover:text-foreground">
          Clientes
        </Link>
      </nav>
      <PageHeader
        title={client.name}
        actions={
          <StatusBadge tone={client.status === 'active' ? 'success' : 'neutral'}>
            {client.status === 'active' ? 'Ativo' : 'Arquivado'}
          </StatusBadge>
        }
      />
      <section aria-labelledby="my-access" className="rounded-lg border bg-surface p-4">
        <h2 id="my-access" className="text-sm font-medium">
          Seu acesso a este cliente
        </h2>
        <ul className="mt-3 flex flex-wrap gap-1.5">
          {capabilities.map((capability) => (
            <li key={capability}>
              <StatusBadge tone="info">{CAPABILITY_LABELS[capability]}</StatusBadge>
            </li>
          ))}
        </ul>
        <p className="mt-3 text-xs text-muted-foreground">
          Conteúdo, aprovações e demais áreas do cliente chegam nos próximos incrementos.
        </p>
      </section>
      {capabilities.includes('client.view') ? (
        <section aria-labelledby="client-brain" className="mt-4 rounded-lg border bg-surface p-4">
          <h2 id="client-brain" className="text-sm font-medium">
            Client Brain
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Marca, públicos, ofertas, regiões, fontes, conhecimento e regras do cliente.
          </p>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}/brain`}
            className="mt-3 inline-flex text-sm font-medium text-primary"
          >
            Abrir Client Brain
          </Link>
        </section>
      ) : null}
      {capabilities.includes('client.view') ? (
        <section
          aria-labelledby="client-meetings"
          className="mt-4 rounded-lg border bg-surface p-4"
        >
          <h2 id="client-meetings" className="text-sm font-medium">
            Reuniões
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Transcrições e conhecimento extraído pela IA local, para revisão.
          </p>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}/meetings`}
            className="mt-3 inline-flex text-sm font-medium text-primary"
          >
            Abrir reuniões
          </Link>
        </section>
      ) : null}
      {capabilities.includes('client.view') ? (
        <section aria-labelledby="client-content" className="mt-4 rounded-lg border bg-surface p-4">
          <h2 id="client-content" className="text-sm font-medium">
            Conteúdo
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Oportunidades, pautas, conteúdos, revisões e validação de regras.
          </p>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}/content`}
            className="mt-3 inline-flex text-sm font-medium text-primary"
          >
            Abrir conteúdo
          </Link>
        </section>
      ) : null}
      {capabilities.includes('client.manage') ? (
        <section aria-labelledby="client-access" className="mt-4 rounded-lg border bg-surface p-4">
          <h2 id="client-access" className="text-sm font-medium">
            Acesso ao portal
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Pessoas do cliente que aprovam, comentam ou acompanham pelo portal.
          </p>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}/access`}
            className="mt-3 inline-flex text-sm font-medium text-primary"
          >
            Gerenciar acesso
          </Link>
        </section>
      ) : null}
      {capabilities.includes('client.view') ? (
        <section aria-labelledby="client-drive" className="mt-4 rounded-lg border bg-surface p-4">
          <h2 id="client-drive" className="text-sm font-medium">
            Drive
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Pasta do cliente no Google Drive: arquivos sincronizados e estado da indexação.
          </p>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}/drive`}
            className="mt-3 inline-flex text-sm font-medium text-primary"
          >
            Abrir Drive
          </Link>
        </section>
      ) : null}
    </>
  );
}
