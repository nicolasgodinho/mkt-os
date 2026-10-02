import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, SelectField, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { capabilityFlags } from '@/lib/content/access';
import { createPauta } from '@/lib/content/actions';
import { CONTENT_STATUS, PAUTA_STATUS } from '@/lib/content/model';
import { listContents, listInitiatives, listPautas } from '@/lib/content/queries';

export const metadata: Metadata = { title: 'Pautas e conteúdos' };

export default async function ContentHomePage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const context = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/content`,
  );
  const { workspace, client } = context;
  const can = await capabilityFlags(workspace.id);
  const [pautas, contents, initiatives] = await Promise.all([
    listPautas(client.id),
    listContents(client.id),
    listInitiatives(client.id),
  ]);
  const base = `/w/${workspace.slug}/clients/${client.id}/content`;
  const pautaTitle = new Map(pautas.map((pauta) => [pauta.id, pauta.title]));

  return (
    <div className="flex flex-col gap-6">
      <section aria-labelledby="section-pautas">
        <h2 id="section-pautas" className="mb-3 text-sm font-medium">
          Pautas
        </h2>
        {pautas.length === 0 ? (
          <EmptyState
            headingLevel={3}
            title="Nenhuma pauta"
            description="Crie uma pauta ou converta uma oportunidade."
          />
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Pautas">
            {pautas.map((pauta) => (
              <li
                key={pauta.id}
                className="flex flex-wrap items-center gap-2 rounded-lg border bg-surface p-3"
              >
                <Link
                  href={`${base}/pautas/${pauta.id}`}
                  className="text-sm font-medium text-primary"
                >
                  {pauta.title}
                </Link>
                <StatusBadge tone={PAUTA_STATUS[pauta.status].tone}>
                  {PAUTA_STATUS[pauta.status].label}
                </StatusBadge>
              </li>
            ))}
          </ul>
        )}
        {can.strategy ? (
          <details className="mt-3 rounded-lg border bg-surface p-3">
            <summary className="cursor-pointer text-sm font-medium text-primary">
              Nova pauta
            </summary>
            <ActionForm
              action={createPauta}
              hidden={{ workspaceSlug: workspace.slug, clientId: client.id }}
              buttons={[{ label: 'Criar pauta' }]}
              resetOnSuccess
              className="mt-3 max-w-xl"
            >
              <TextField
                id="pauta-title"
                name="title"
                label="Título da pauta"
                required
                maxLength={300}
              />
              <SelectField
                id="pauta-initiative"
                name="initiativeId"
                label="Iniciativa (opcional)"
                options={[
                  { value: '', label: 'Nenhuma' },
                  ...initiatives.map((initiative) => ({
                    value: initiative.id,
                    label: initiative.name,
                  })),
                ]}
              />
            </ActionForm>
          </details>
        ) : null}
      </section>

      <section aria-labelledby="section-contents">
        <h2 id="section-contents" className="mb-3 text-sm font-medium">
          Conteúdos
        </h2>
        {contents.length === 0 ? (
          <EmptyState
            headingLevel={3}
            title="Nenhum conteúdo"
            description="Conteúdos nascem de uma pauta pronta (Definition of Ready completo)."
          />
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Conteúdos">
            {contents.map((content) => (
              <li
                key={content.id}
                className="flex flex-wrap items-center gap-2 rounded-lg border bg-surface p-3"
              >
                <Link
                  href={`${base}/items/${content.id}`}
                  className="text-sm font-medium text-primary"
                >
                  {content.title}
                </Link>
                <StatusBadge tone={CONTENT_STATUS[content.status].tone}>
                  {CONTENT_STATUS[content.status].label}
                </StatusBadge>
                <span className="text-xs text-muted-foreground">
                  {content.channel} · {content.format} · pauta:{' '}
                  {pautaTitle.get(content.pauta_id) ?? '—'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
