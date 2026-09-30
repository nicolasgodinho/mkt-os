import type { Metadata } from 'next';
import { EmptyState, PageHeader } from '@jmos/ui';

export const metadata: Metadata = { title: 'Portal' };

export default function PortalHomePage() {
  return (
    <>
      <PageHeader title="Início" description="O que precisa da sua atenção agora." />
      <EmptyState
        title="Portal em construção"
        description="Aprovações, próximos 7 dias e trabalhos em andamento aparecerão aqui."
      />
    </>
  );
}
