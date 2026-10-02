import type { ReactNode } from 'react';
import Link from 'next/link';
import { PageHeader } from '@jmos/ui';
import { SectionTabs } from '@/components/section-tabs';
import { resolveBrainContext } from '@/lib/brain/context';

/**
 * Client content hub (docs/07 §6–§8): pautas and contents, opportunities and initiatives.
 * Internal-only in Increment 5; client review arrives in Increment 6.
 */
export default async function ContentLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { workspace, client } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/content`,
  );
  const base = `/w/${workspace.slug}/clients/${client.id}/content`;

  return (
    <>
      <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
        <Link href={`/w/${workspace.slug}/clients`} className="hover:text-foreground">
          Clientes
        </Link>
        <span aria-hidden> / </span>
        <Link href={`/w/${workspace.slug}/clients/${client.id}`} className="hover:text-foreground">
          {client.name}
        </Link>
      </nav>
      <PageHeader
        title={`Conteúdo: ${client.name}`}
        description="Da oportunidade à revisão aprovada: pautas com Definition of Ready, conteúdos e revisões imutáveis."
      />
      <SectionTabs
        label="Seções de conteúdo"
        tabs={[
          {
            href: base,
            label: 'Pautas e conteúdos',
            prefixes: [`${base}/pautas`, `${base}/items`],
          },
          { href: `${base}/opportunities`, label: 'Oportunidades' },
          { href: `${base}/initiatives`, label: 'Iniciativas' },
        ]}
      />
      {children}
    </>
  );
}
