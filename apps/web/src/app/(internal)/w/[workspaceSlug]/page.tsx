import type { Metadata } from 'next';
import Link from 'next/link';
import { Construction } from 'lucide-react';
import { EmptyState, PageHeader } from '@jmos/ui';
import { requireSessionUser } from '@/lib/auth/session';

export const metadata: Metadata = { title: 'Início' };

export default async function WorkspaceHomePage({
  params,
}: {
  params: Promise<{ workspaceSlug: string }>;
}) {
  const { workspaceSlug } = await params;
  await requireSessionUser(`/w/${workspaceSlug}`);
  return (
    <>
      <PageHeader title="Início" description="O que precisa de atenção hoje." />
      <EmptyState
        icon={<Construction aria-hidden className="size-6" />}
        title="Módulo em construção"
        description="Precisa de atenção, agenda do dia, aprovações e solicitações pendentes chegam nos próximos incrementos."
        action={
          <Link href={`/w/${workspaceSlug}/clients`} className="text-sm font-medium text-primary">
            Ver clientes
          </Link>
        }
      />
    </>
  );
}
