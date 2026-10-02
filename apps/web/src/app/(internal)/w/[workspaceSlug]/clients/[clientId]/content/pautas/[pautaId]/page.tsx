import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { SelectField, StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { resolveBrainContext } from '@/lib/brain/context';
import { listAudiences, listOffers, listSources } from '@/lib/brain/queries';
import { capabilityFlags } from '@/lib/content/access';
import { createContent, savePauta } from '@/lib/content/actions';
import { CONTENT_STATUS, DOR_FIELDS, DOR_LABELS, PAUTA_STATUS } from '@/lib/content/model';
import { getPauta, getPautaReadiness, listContents } from '@/lib/content/queries';
import { isUuid } from '@/lib/identity/routing';

export const metadata: Metadata = { title: 'Pauta' };

/** Pauta Detail (docs/07 §7): why it exists, the brief, the Definition of Ready, executions. */
export default async function PautaPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string; pautaId: string }>;
}) {
  const { workspaceSlug, clientId, pautaId } = await params;
  const { workspace, client } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/content/pautas/${pautaId}`,
  );
  if (!isUuid(pautaId)) notFound();
  const pauta = await getPauta(client.id, pautaId);
  if (pauta === null) notFound();
  const can = await capabilityFlags(workspace.id);
  const [readiness, contents, audiences, offers, sources] = await Promise.all([
    getPautaReadiness(pauta.id),
    listContents(client.id, pauta.id),
    listAudiences(client.id),
    listOffers(client.id),
    listSources(client.id),
  ]);
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };
  const base = `/w/${workspace.slug}/clients/${client.id}/content`;
  const evidence = sources.filter((source) => pauta.source_ids.includes(source.id));
  // Archived items already on the pauta stay selectable so saving never drops them silently.
  const selectableAudiences = audiences.filter(
    (audience) => audience.status === 'active' || pauta.audience_ids.includes(audience.id),
  );

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="text-lg font-semibold">{pauta.title}</h2>
        <StatusBadge tone={PAUTA_STATUS[pauta.status].tone}>
          {PAUTA_STATUS[pauta.status].label}
        </StatusBadge>
      </div>

      <section aria-labelledby="section-dor" className="rounded-lg border bg-surface p-4">
        <h3 id="section-dor" className="text-sm font-medium">
          Definition of Ready
        </h3>
        <ul
          className="mt-2 flex flex-col gap-1 text-sm"
          aria-label="Checklist do Definition of Ready"
        >
          {DOR_FIELDS.map((field) => {
            const ok = readiness.get(field) === true;
            return (
              <li key={field} className="flex items-center gap-2">
                <StatusBadge tone={ok ? 'success' : 'warning'}>{ok ? 'OK' : 'Falta'}</StatusBadge>
                {DOR_LABELS[field]}
              </li>
            );
          })}
        </ul>
        <p className="mt-2 text-xs text-muted-foreground">
          Por que existe:{' '}
          {evidence.length === 0 ? 'nenhuma fonte ligada' : evidence.map((s) => s.title).join(', ')}
        </p>
      </section>

      <section aria-labelledby="section-brief" className="rounded-lg border bg-surface p-4">
        <h3 id="section-brief" className="text-sm font-medium">
          Briefing
        </h3>
        {can.strategy ? (
          <ActionForm
            action={savePauta}
            hidden={{ ...scope, id: pauta.id }}
            buttons={[
              { label: 'Salvar', value: 'save', variant: 'secondary' },
              ...(pauta.status === 'draft'
                ? [{ label: 'Salvar e marcar pronta', value: 'ready' }]
                : []),
            ]}
            className="mt-3 max-w-2xl"
          >
            <TextAreaField
              id="pauta-objective"
              name="objective"
              label="Objetivo"
              maxLength={2000}
              defaultValue={pauta.objective ?? ''}
            />
            <fieldset>
              <legend className="mb-1 text-sm font-medium">Público</legend>
              {selectableAudiences.length === 0 ? (
                <p className="text-xs text-muted-foreground">Cadastre públicos no Client Brain.</p>
              ) : (
                <div className="flex flex-wrap gap-3">
                  {selectableAudiences.map((audience) => (
                    <label key={audience.id} className="flex items-center gap-1.5 text-sm">
                      <input
                        type="checkbox"
                        name="audienceIds"
                        value={audience.id}
                        defaultChecked={pauta.audience_ids.includes(audience.id)}
                      />
                      {audience.name}
                      {audience.status === 'archived' ? ' (arquivado)' : ''}
                    </label>
                  ))}
                </div>
              )}
            </fieldset>
            <div className="grid gap-3 sm:grid-cols-2">
              <TextField
                id="pauta-pillar"
                name="pillar"
                label="Pilar"
                maxLength={200}
                defaultValue={pauta.pillar ?? ''}
              />
              <TextField
                id="pauta-cta"
                name="cta"
                label="CTA"
                maxLength={300}
                defaultValue={pauta.cta ?? ''}
              />
            </div>
            <TextAreaField
              id="pauta-message"
              name="message"
              label="Mensagem"
              maxLength={2000}
              defaultValue={pauta.message ?? ''}
            />
            <TextAreaField
              id="pauta-angle"
              name="angle"
              label="Ângulo"
              maxLength={2000}
              defaultValue={pauta.angle ?? ''}
            />
            <SelectField
              id="pauta-offer"
              name="offerId"
              label="Oferta"
              defaultValue={pauta.offer_id ?? ''}
              options={[
                { value: '', label: 'Nenhuma' },
                ...offers
                  .filter((o) => o.status === 'active' || o.id === pauta.offer_id)
                  .map((o) => ({
                    value: o.id,
                    label: o.status === 'active' ? o.name : `${o.name} (arquivada)`,
                  })),
              ]}
            />
            <TextAreaField
              id="pauta-mandatories"
              name="mandatories"
              label="Obrigatório citar"
              maxLength={4000}
              defaultValue={pauta.mandatories ?? ''}
            />
            <TextAreaField
              id="pauta-constraints"
              name="constraints"
              label="Não pode / restrições"
              maxLength={4000}
              defaultValue={pauta.constraints ?? ''}
            />
          </ActionForm>
        ) : (
          <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-[10rem_1fr]">
            {(
              [
                ['Objetivo', pauta.objective],
                ['Mensagem', pauta.message],
                ['Ângulo', pauta.angle],
                ['CTA', pauta.cta],
                ['Obrigatório citar', pauta.mandatories],
                ['Restrições', pauta.constraints],
              ] as const
            ).map(([label, value]) => (
              <div key={label} className="contents">
                <dt className="font-medium">{label}</dt>
                <dd className="text-muted-foreground">{value ?? 'Não informado'}</dd>
              </div>
            ))}
          </dl>
        )}
      </section>

      <section aria-labelledby="section-executions">
        <h3 id="section-executions" className="mb-3 text-sm font-medium">
          Execuções
        </h3>
        {contents.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum conteúdo para esta pauta ainda.</p>
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Execuções da pauta">
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
                  {content.channel} · {content.format}
                </span>
              </li>
            ))}
          </ul>
        )}
        {can.create && pauta.status === 'ready' ? (
          <details className="mt-3 rounded-lg border bg-surface p-3">
            <summary className="cursor-pointer text-sm font-medium text-primary">
              Novo conteúdo
            </summary>
            <ActionForm
              action={createContent}
              hidden={{ ...scope, pautaId: pauta.id }}
              buttons={[{ label: 'Criar conteúdo' }]}
              resetOnSuccess
              className="mt-3 max-w-xl"
            >
              <TextField
                id="content-title"
                name="title"
                label="Título do conteúdo"
                required
                maxLength={300}
              />
              <div className="grid gap-3 sm:grid-cols-2">
                <TextField
                  id="content-channel"
                  name="channel"
                  label="Canal"
                  placeholder="instagram"
                  required
                  maxLength={40}
                />
                <TextField
                  id="content-format"
                  name="format"
                  label="Formato"
                  placeholder="post"
                  required
                  maxLength={40}
                />
              </div>
            </ActionForm>
          </details>
        ) : pauta.status !== 'ready' ? (
          <p className="mt-2 text-xs text-muted-foreground">
            Conteúdos só podem ser criados quando a pauta estiver pronta (Definition of Ready
            completo).
          </p>
        ) : null}
      </section>
    </div>
  );
}
