import type { Metadata } from 'next';
import { Construction } from 'lucide-react';
import { EmptyState, PageHeader } from '@jmos/ui';

export const metadata: Metadata = { title: 'Início' };

export default function InternalHomePage() {
  return (
    <>
      <PageHeader title="Início" description="O que precisa de atenção hoje." />
      <EmptyState
        icon={<Construction aria-hidden className="size-6" />}
        title="Módulo em construção"
        description="Precisa de atenção, agenda do dia, aprovações e solicitações pendentes chegam nos próximos incrementos."
      />
    </>
  );
}
