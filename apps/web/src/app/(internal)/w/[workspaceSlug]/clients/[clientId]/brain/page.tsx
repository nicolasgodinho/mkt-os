import type { Metadata } from 'next';
import { TextAreaField } from '@jmos/ui';
import { BrainForm } from '@/components/brain/brain-form';
import { ContextSection } from '@/components/brain/context-section';
import { saveBrandProfile } from '@/lib/brain/actions';
import { resolveBrainContext } from '@/lib/brain/context';
import { formatDate } from '@/lib/brain/model';
import { getBrandProfile, listAudiences, listOffers, listRegions } from '@/lib/brain/queries';

export const metadata: Metadata = { title: 'Client Brain' };

/** Client Brain overview: business, brand, voice, audiences, offers and regions (docs/07 §4). */
export default async function BrainOverviewPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { client, workspace, can } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/brain`,
  );
  const [profile, audiences, offers, regions] = await Promise.all([
    getBrandProfile(client.id),
    listAudiences(client.id),
    listOffers(client.id),
    listRegions(client.id),
  ]);
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };

  const profileFields = [
    { name: 'business', label: 'Negócio', value: profile?.business ?? '' },
    { name: 'brand', label: 'Marca', value: profile?.brand ?? '' },
    { name: 'voice', label: 'Voz e tom', value: profile?.voice ?? '' },
  ] as const;
  const visualReferences = profile?.visual_references ?? [];

  return (
    <div className="flex flex-col gap-6">
      <section aria-labelledby="section-brand" className="rounded-lg border bg-surface p-4">
        <h2 id="section-brand" className="text-sm font-medium">
          Negócio, marca e voz
        </h2>
        {can.editStrategy ? (
          <BrainForm
            action={saveBrandProfile}
            hidden={scope}
            submitLabel="Salvar perfil da marca"
            className="mt-3 max-w-2xl"
          >
            {profileFields.map((field) => (
              <TextAreaField
                key={field.name}
                id={`brand-${field.name}`}
                name={field.name}
                label={field.label}
                maxLength={4000}
                defaultValue={field.value}
              />
            ))}
            <TextAreaField
              id="brand-visual-references"
              name="visualReferences"
              label="Referências visuais (um link por linha)"
              maxLength={8000}
              defaultValue={visualReferences.join('\n')}
            />
          </BrainForm>
        ) : profile === null ? (
          <p className="mt-3 text-sm text-muted-foreground">
            O perfil da marca ainda não foi preenchido.
          </p>
        ) : (
          <dl className="mt-3 grid gap-3 text-sm sm:grid-cols-[10rem_1fr]">
            {profileFields.map((field) => (
              <div key={field.name} className="contents">
                <dt className="font-medium">{field.label}</dt>
                <dd className="whitespace-pre-line text-muted-foreground">
                  {field.value || 'Não informado'}
                </dd>
              </div>
            ))}
            <dt className="font-medium">Referências visuais</dt>
            <dd className="text-muted-foreground">
              {visualReferences.length === 0 ? (
                'Não informado'
              ) : (
                <ul>
                  {visualReferences.map((reference) => (
                    <li key={reference} className="break-all">
                      {reference}
                    </li>
                  ))}
                </ul>
              )}
            </dd>
          </dl>
        )}
        {profile !== null ? (
          <p className="mt-3 text-xs text-muted-foreground">
            Atualizado em {formatDate(profile.updated_at)}
          </p>
        ) : null}
      </section>

      <div className="grid gap-6 lg:grid-cols-3">
        <ContextSection
          kind="audience"
          title="Públicos"
          addLabel="Adicionar público"
          emptyLabel="Nenhum público cadastrado."
          items={audiences}
          scope={scope}
          canEdit={can.editStrategy}
        />
        <ContextSection
          kind="offer"
          title="Ofertas"
          addLabel="Adicionar oferta"
          emptyLabel="Nenhuma oferta cadastrada."
          items={offers}
          scope={scope}
          canEdit={can.editStrategy}
        />
        <ContextSection
          kind="region"
          title="Regiões"
          addLabel="Adicionar região"
          emptyLabel="Nenhuma região cadastrada."
          items={regions}
          scope={scope}
          canEdit={can.editStrategy}
        />
      </div>
    </div>
  );
}
