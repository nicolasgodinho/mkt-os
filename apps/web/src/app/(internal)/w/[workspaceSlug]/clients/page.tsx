import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Users } from 'lucide-react';
import { EmptyState, PageHeader, StatusBadge } from '@jmos/ui';
import { requireSessionUser } from '@/lib/auth/session';
import { getWorkspaceBySlug, listWorkspaceClients } from '@/lib/identity/queries';

export const metadata: Metadata = { title: 'Clientes' };

export default async function ClientsPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string }>;
}) {
  const { workspaceSlug } = await params;
  // Pages render in parallel with layouts, so every page checks the session itself.
  await requireSessionUser(`/w/${workspaceSlug}/clients`);
  const workspace = await getWorkspaceBySlug(workspaceSlug);
  if (workspace === null) notFound();
  // Row level security returns only the clients this member may see (docs/05 §1).
  const clients = await listWorkspaceClients(workspace.id);

  return (
    <>
      <PageHeader
        title="Clientes"
        description={`Clientes disponíveis para você em ${workspace.name}.`}
      />
      {clients.length === 0 ? (
        <EmptyState
          icon={<Users aria-hidden className="size-6" />}
          title="Nenhum cliente disponível"
          description="Você ainda não tem acesso a clientes deste workspace. Peça a um administrador para liberar o acesso."
        />
      ) : (
        <div className="overflow-hidden rounded-lg border bg-surface">
          <table className="w-full text-sm">
            <caption className="sr-only">Clientes</caption>
            <thead className="border-b bg-surface-muted text-left text-xs text-muted-foreground">
              <tr>
                <th scope="col" className="px-4 py-2 font-medium">
                  Cliente
                </th>
                <th scope="col" className="px-4 py-2 font-medium">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {clients.map((client) => (
                <tr key={client.id} className="border-b last:border-b-0">
                  <td className="px-4 py-2">
                    <Link
                      href={`/w/${workspace.slug}/clients/${client.id}`}
                      className="font-medium hover:underline"
                    >
                      {client.name}
                    </Link>
                  </td>
                  <td className="px-4 py-2">
                    <StatusBadge tone={client.status === 'active' ? 'success' : 'neutral'}>
                      {client.status === 'active' ? 'Ativo' : 'Arquivado'}
                    </StatusBadge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
