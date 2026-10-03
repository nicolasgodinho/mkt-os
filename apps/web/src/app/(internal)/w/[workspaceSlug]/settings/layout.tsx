import type { ReactNode } from 'react';
import { PageHeader } from '@jmos/ui';
import { SectionTabs } from '@/components/section-tabs';

/** Workspace settings (docs/06 "Settings"): the team and the clients. Each page checks access. */
export default async function SettingsLayout({
  children,
  params,
}: {
  children: ReactNode;
  params: Promise<{ workspaceSlug: string }>;
}) {
  const { workspaceSlug } = await params;
  const base = `/w/${workspaceSlug}/settings`;
  return (
    <>
      <PageHeader
        title="Configurações"
        description="Quem acessa o workspace e quais clientes ele atende."
      />
      <SectionTabs
        label="Seções de configurações"
        tabs={[
          { href: base, label: 'Equipe' },
          { href: `${base}/clients`, label: 'Clientes' },
        ]}
      />
      {children}
    </>
  );
}
