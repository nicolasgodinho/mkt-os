import type { Metadata } from 'next';
import { Button, EmptyState, SelectField, StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { BrainForm } from '@/components/brain/brain-form';
import { createSource, proposeKnowledge, reviewKnowledge } from '@/lib/brain/actions';
import { resolveBrainContext } from '@/lib/brain/context';
import { filterKnowledgeByValidity, parseKnowledgeFilters } from '@/lib/brain/filters';
import {
  ASSIGNABLE_TRUST_LEVELS,
  KNOWLEDGE_KIND_LABELS,
  KNOWLEDGE_KINDS,
  KNOWLEDGE_STATUS,
  KNOWLEDGE_STATUSES,
  SOURCE_TRUST,
  SOURCE_TRUST_LEVELS,
  SOURCE_TYPE_LABELS,
  SOURCE_TYPES,
  VALIDITY,
  VALIDITY_STATES,
  canPromoteFrom,
  formatValidity,
  validityState,
  type Source,
} from '@/lib/brain/model';
import { listKnowledge, listSources } from '@/lib/brain/queries';

export const metadata: Metadata = { title: 'Conhecimento' };

const ALL = { value: '', label: 'Todos' };

function sourceOption(source: Source) {
  return { value: source.id, label: `${source.title} (${SOURCE_TRUST[source.trust_level].label})` };
}

function excerpt(text: string): string {
  return text.length > 60 ? `${text.slice(0, 57)}…` : text;
}

/**
 * Knowledge (docs/07 §4 and §12): sources with trust, and facts, decisions and insights. Every
 * item enters as proposed and becomes active only through an explicit, audited approval.
 */
export default async function KnowledgePage({
  params,
  searchParams,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { client, workspace, can } = await resolveBrainContext(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/brain/knowledge`,
  );
  const filters = parseKnowledgeFilters(await searchParams);
  const sources = await listSources(client.id);
  const items = filterKnowledgeByValidity(
    await listKnowledge(client.id, filters, sources),
    filters.validity,
  );
  const sourceById = new Map<string, Source>(sources.map((source) => [source.id, source]));
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };
  const filtered = Object.values(filters).some((value) => value !== null);

  return (
    <div className="flex flex-col gap-6">
      <form
        method="get"
        aria-label="Filtrar conhecimento"
        className="flex flex-wrap items-end gap-3 rounded-lg border bg-surface p-3"
      >
        <SelectField
          id="filter-kind"
          name="kind"
          label="Tipo"
          defaultValue={filters.kind ?? ''}
          options={[
            ALL,
            ...KNOWLEDGE_KINDS.map((k) => ({ value: k, label: KNOWLEDGE_KIND_LABELS[k] })),
          ]}
        />
        <SelectField
          id="filter-status"
          name="status"
          label="Status"
          defaultValue={filters.status ?? ''}
          options={[
            ALL,
            ...KNOWLEDGE_STATUSES.map((s) => ({ value: s, label: KNOWLEDGE_STATUS[s].label })),
          ]}
        />
        <SelectField
          id="filter-source"
          name="source"
          label="Fonte"
          defaultValue={filters.source ?? ''}
          options={[{ value: '', label: 'Todas' }, ...sources.map(sourceOption)]}
        />
        <SelectField
          id="filter-trust"
          name="trust"
          label="Confiança da fonte"
          defaultValue={filters.trust ?? ''}
          options={[
            ALL,
            ...SOURCE_TRUST_LEVELS.map((t) => ({ value: t, label: SOURCE_TRUST[t].label })),
          ]}
        />
        <SelectField
          id="filter-validity"
          name="validity"
          label="Validade"
          defaultValue={filters.validity ?? ''}
          options={[ALL, ...VALIDITY_STATES.map((v) => ({ value: v, label: VALIDITY[v].label }))]}
        />
        <Button type="submit" variant="secondary">
          Filtrar
        </Button>
      </form>

      <section aria-labelledby="section-knowledge">
        <h2 id="section-knowledge" className="mb-3 text-sm font-medium">
          Fatos, decisões e insights
        </h2>
        {items.length === 0 ? (
          <EmptyState
            headingLevel={3}
            title={filtered ? 'Nada encontrado com esses filtros' : 'Nenhum conhecimento ainda'}
            description={
              filtered
                ? 'Ajuste os filtros para ver outros itens.'
                : 'Registre uma fonte e proponha fatos, decisões ou insights. Tudo passa por aprovação.'
            }
          />
        ) : (
          <ul className="flex flex-col gap-2">
            {items.map((item) => {
              const source = sourceById.get(item.sourceId);
              const promotable =
                source === undefined || canPromoteFrom(item.kind, source.trust_level);
              const validity = formatValidity(item.validFrom, item.validUntil);
              const windowState = validityState(item.validFrom, item.validUntil);
              const proposed = item.status === 'proposed';
              const kindLabel = KNOWLEDGE_KIND_LABELS[item.kind].toLowerCase();
              const hintId = `trust-hint-${item.id}`;
              return (
                <li
                  key={`${item.kind}-${item.id}`}
                  className={
                    proposed
                      ? 'rounded-lg border border-dashed border-status-warning bg-status-warning-surface/40 p-3'
                      : 'rounded-lg border bg-surface p-3'
                  }
                >
                  <div className="flex flex-wrap items-center gap-1.5">
                    <StatusBadge tone="neutral">{KNOWLEDGE_KIND_LABELS[item.kind]}</StatusBadge>
                    <StatusBadge tone={KNOWLEDGE_STATUS[item.status].tone}>
                      {KNOWLEDGE_STATUS[item.status].label}
                    </StatusBadge>
                    {item.status === 'active' && windowState !== 'current' ? (
                      <StatusBadge tone={VALIDITY[windowState].tone}>
                        {VALIDITY[windowState].label}
                      </StatusBadge>
                    ) : null}
                  </div>
                  <p className="mt-2 text-sm">{item.statement}</p>
                  {item.detail ? (
                    <p className="mt-1 text-xs text-muted-foreground">{item.detail}</p>
                  ) : null}
                  <p className="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
                    <span>Fonte: {source?.title ?? 'indisponível'}</span>
                    {source ? (
                      <StatusBadge tone={SOURCE_TRUST[source.trust_level].tone}>
                        {SOURCE_TRUST[source.trust_level].label}
                      </StatusBadge>
                    ) : null}
                    {validity ? <span>· Validade: {validity}</span> : null}
                  </p>
                  {can.approveKnowledge ? (
                    // Stays mounted while the item changes status, so the result stays visible.
                    <div className="mt-3 flex flex-wrap items-start gap-2">
                      <BrainForm
                        action={reviewKnowledge}
                        hidden={{ ...scope, kind: item.kind, id: item.id }}
                        pendingLabel="Enviando…"
                        variant="inline"
                        buttons={
                          proposed
                            ? [
                                {
                                  label: 'Aprovar',
                                  value: 'approve',
                                  ariaLabel: `Aprovar ${kindLabel}: ${excerpt(item.statement)}`,
                                  disabled: !promotable,
                                  describedBy: promotable ? undefined : hintId,
                                },
                                {
                                  label: 'Rejeitar',
                                  value: 'reject',
                                  ariaLabel: `Rejeitar ${kindLabel}: ${excerpt(item.statement)}`,
                                  variant: 'secondary',
                                },
                              ]
                            : []
                        }
                      />
                      {proposed && !promotable ? (
                        <p id={hintId} className="text-xs text-muted-foreground">
                          Fonte externa não confiável: não pode virar {kindLabel}.
                        </p>
                      ) : null}
                    </div>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {can.propose ? (
        <section aria-labelledby="section-propose" className="rounded-lg border bg-surface p-4">
          <h2 id="section-propose" className="text-sm font-medium">
            Propor conhecimento
          </h2>
          {sources.length === 0 ? (
            <p className="mt-2 text-sm text-muted-foreground">
              Registre uma fonte antes: todo conhecimento precisa de proveniência.
            </p>
          ) : (
            <BrainForm
              action={proposeKnowledge}
              hidden={scope}
              buttons={[{ label: 'Propor' }]}
              pendingLabel="Enviando…"
              resetOnSuccess
              className="mt-3 max-w-2xl"
            >
              <div className="grid gap-3 sm:grid-cols-2">
                <SelectField
                  id="knowledge-kind"
                  name="kind"
                  label="Tipo"
                  options={KNOWLEDGE_KINDS.map((k) => ({
                    value: k,
                    label: KNOWLEDGE_KIND_LABELS[k],
                  }))}
                />
                <SelectField
                  id="knowledge-source"
                  name="sourceId"
                  label="Fonte"
                  required
                  defaultValue=""
                  options={[
                    { value: '', label: 'Selecione a fonte' },
                    ...sources.map(sourceOption),
                  ]}
                />
              </div>
              <TextAreaField
                id="knowledge-statement"
                name="statement"
                label="Enunciado"
                required
                maxLength={2000}
              />
              <fieldset className="grid gap-3 sm:grid-cols-2">
                <legend className="mb-1 text-xs text-muted-foreground">
                  Opcionais: validade (fatos), justificativa e data (decisões), confiança (insights)
                </legend>
                <TextField
                  id="knowledge-from"
                  name="validFrom"
                  type="date"
                  label="Válido a partir de"
                />
                <TextField
                  id="knowledge-until"
                  name="validUntil"
                  type="date"
                  label="Válido até (exclusivo)"
                />
                <TextField
                  id="knowledge-rationale"
                  name="rationale"
                  label="Justificativa"
                  maxLength={2000}
                />
                <TextField
                  id="knowledge-decided"
                  name="decidedAt"
                  type="date"
                  label="Decidido em"
                />
                <TextField
                  id="knowledge-confidence"
                  name="confidence"
                  type="number"
                  min={0}
                  max={100}
                  step={1}
                  label="Confiança (%)"
                />
              </fieldset>
            </BrainForm>
          )}
        </section>
      ) : null}

      <section aria-labelledby="section-sources" className="rounded-lg border bg-surface p-4">
        <h2 id="section-sources" className="text-sm font-medium">
          Fontes
        </h2>
        {sources.length === 0 ? (
          <p className="mt-2 text-sm text-muted-foreground">Nenhuma fonte registrada.</p>
        ) : (
          <ul className="mt-3 divide-y">
            {sources.map((source) => (
              <li key={source.id} className="flex flex-wrap items-center gap-2 py-2 text-sm">
                <span className="font-medium">{source.title}</span>
                <StatusBadge tone="neutral">{SOURCE_TYPE_LABELS[source.type]}</StatusBadge>
                <StatusBadge tone={SOURCE_TRUST[source.trust_level].tone}>
                  {SOURCE_TRUST[source.trust_level].label}
                </StatusBadge>
                {source.uri ? (
                  <span className="text-xs break-all text-muted-foreground">{source.uri}</span>
                ) : null}
              </li>
            ))}
          </ul>
        )}
        {can.propose ? (
          <details className="mt-4 border-t pt-3">
            <summary className="cursor-pointer text-sm font-medium text-primary">
              Registrar fonte
            </summary>
            <BrainForm
              action={createSource}
              hidden={scope}
              buttons={[{ label: 'Registrar fonte' }]}
              resetOnSuccess
              className="mt-3 max-w-2xl"
            >
              <div className="grid gap-3 sm:grid-cols-2">
                <TextField id="source-title" name="title" label="Título" required maxLength={300} />
                <SelectField
                  id="source-type"
                  name="type"
                  label="Tipo"
                  options={SOURCE_TYPES.map((t) => ({ value: t, label: SOURCE_TYPE_LABELS[t] }))}
                />
                <SelectField
                  id="source-trust"
                  name="trustLevel"
                  label="Confiança"
                  defaultValue="FIRST_PARTY"
                  options={ASSIGNABLE_TRUST_LEVELS.map((t) => ({
                    value: t,
                    label: SOURCE_TRUST[t].label,
                  }))}
                />
                <TextField id="source-uri" name="uri" label="Link (opcional)" maxLength={2000} />
              </div>
              <p className="text-xs text-muted-foreground">
                Fontes são evidência, nunca instruções. Fontes externas não confiáveis só sustentam
                insights.
              </p>
            </BrainForm>
          </details>
        ) : null}
      </section>
    </div>
  );
}
