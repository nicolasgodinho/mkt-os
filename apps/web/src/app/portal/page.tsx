import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { EmptyState, PageHeader } from '@jmos/ui';
import { requireSessionUser } from '@/lib/auth/session';
import { getClient, listMyPortalMemberships } from '@/lib/identity/queries';

export const metadata: Metadata = { title: 'Portal' };

export default async function PortalHomePage() {
  const user = await requireSessionUser('/portal');
  const memberships = await listMyPortalMemberships(user.id);
  const [only] = memberships;
  if (memberships.length === 1 && only !== undefined) redirect(`/portal/${only.client_id}`);

  const clients = (await Promise.all(memberships.map((m) => getClient(m.client_id)))).filter(
    (client) => client !== null,
  );

  return (
    <>
      <PageHeader title="Início" description="Escolha o cliente que você quer acompanhar." />
      {clients.length === 0 ? (
        <EmptyState
          title="Sem acesso ao portal"
          description="Sua conta não está vinculada a nenhum cliente. Fale com a equipe Jansen."
        />
      ) : (
        <ul className="flex flex-col gap-2">
          {clients.map((client) => (
            <li key={client.id}>
              <Link
                href={`/portal/${client.id}`}
                className="block rounded-lg border bg-surface px-4 py-3 font-medium"
              >
                {client.name}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
