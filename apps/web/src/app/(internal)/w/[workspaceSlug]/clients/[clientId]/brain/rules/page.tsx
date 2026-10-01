import type { Metadata } from 'next';
import { Button, EmptyState, SelectField, StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { BrainForm } from '@/components/brain/brain-form';
import { proposeRule, reviewRule } from '@/lib/brain/actions';
import { resolveBrainContext } from '@/lib/brain/context';
import { filterRules, parseRuleFilters } from '@/lib/brain/filters';
import {
  RULE_STATUS,
  RULE_STATUSES,
  RULE_TYPE_LABELS,
  RULE_TYPES,
  SOURCE_TRUST,
  canPromoteFrom,
  formatValidity,
  type Rule,
  type Source,
} from '@/lib/brain/model';
import { listEffectiveRules, listRuleConflicts, listRules, listSources } from '@/lib/brain/queries';

export const metadata: Metadata = { title: 'Regras' };

const ALL = { value: '', label: 'Todos' };

function scopeLabel(rule: Pick<Rule, 'scope_type' | 'channel'>): string {
  return rule.scope_type === 'channel' && rule.channel !== null
    ? `Canal: ${rule.channel}`
    : 'Cliente (todos os canais)';
}

/**
 * Rules (docs/02 §4, docs/04 Rule, docs/07 §12). Activation requires `rule.activate`; opposite
 * hard rules on the same subject, scope and priority conflict and stay out of the effective set
 * until a person rejects or supersedes one of them.
 */
export default async function RulesPage({
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
    `/w/${workspaceSlug}/clients/${clientId}/brain/rules`,
  );
  const filters = parseRuleFilters(await searchParams);
  const [rules, sources, conflicts, effective] = await Promise.all([
    listRules(client.id),
    listSources(client.id),
    listRuleConflicts(client.id),
    listEffectiveRules(client.id, filters.channel),
  ]);
  const sourceById = new Map<string, Source>(sources.map((source) => [source.id, source]));
  const ruleById = new Map<string, Rule>(rules.map((rule) => [rule.id, rule]));
  const visible = filterRules(rules, filters);
  const supersedable = rules.filter(
    (rule) => rule.status === 'active' || rule.status === 'conflict',
  );
  const scope = { workspaceSlug: workspace.slug, clientId: client.id };
  const filtered = filters.type !== null || filters.status !== null || filters.scope !== null;
  const subjects = [...new Set(rules.map((rule) => rule.subject).filter((s) => s !== null))];

  return (
    <div className="flex flex-col gap-6">
      {conflicts.length > 0 ? (
        <section
          aria-labelledby="section-conflicts"
          className="rounded-lg border border-status-danger p-4"
        >
          <h2 id="section-conflicts" className="text-sm font-medium text-status-danger">
            Conflitos a resolver
          </h2>
          <p className="mt-1 text-xs text-muted-foreground">
            Rejeite um dos lados ou proponha uma regra que substitua um deles. O sistema não escolhe
            um vencedor.
          </p>
          <ul className="mt-3 divide-y">
            {conflicts.map((rule) => (
              <li key={rule.id} className="flex flex-wrap items-start justify-between gap-3 py-2">
                <div className="min-w-0">
                  <p className="flex flex-wrap items-center gap-1.5 text-xs">
                    <StatusBadge tone="danger">{RULE_TYPE_LABELS[rule.type]}</StatusBadge>
                    <span className="font-medium">{rule.subject}</span>
                    <span className="text-muted-foreground">
                      · {scopeLabel(rule)} · prioridade {rule.priority.toString()}
                    </span>
                  </p>
                  <p className="mt-1 text-sm">{rule.statement}</p>
                </div>
                {can.activateRules ? (
                  <BrainForm
                    action={reviewRule}
                    hidden={{ ...scope, id: rule.id, decision: 'reject' }}
                    submitLabel="Rejeitar este lado"
                    pendingLabel="Rejeitando…"
                    submitVariant="secondary"
                    variant="inline"
                  />
                ) : null}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section aria-labelledby="section-effective" className="rounded-lg border bg-surface p-4">
        <h2 id="section-effective" className="text-sm font-medium">
          Regras efetivas hoje
        </h2>
        <form
          method="get"
          className="mt-3 flex flex-wrap items-end gap-3"
          aria-label="Escolher canal"
        >
          <TextField
            id="effective-channel"
            name="channel"
            label="Canal (vazio = regras do cliente)"
            placeholder="instagram"
            defaultValue={filters.channel ?? ''}
            maxLength={40}
          />
          <Button type="submit" variant="secondary">
            Ver
          </Button>
        </form>
        {effective.length === 0 ? (
          <p className="mt-3 text-sm text-muted-foreground">Nenhuma regra efetiva.</p>
        ) : (
          <ul className="mt-3 divide-y" aria-label="Regras efetivas">
            {effective.map((rule) => (
              <li key={rule.id} className="py-2 text-sm">
                <span className="mr-2 inline-flex">
                  <StatusBadge tone="info">{RULE_TYPE_LABELS[rule.type]}</StatusBadge>
                </span>
                {rule.subject ? <span className="mr-1 font-medium">[{rule.subject}]</span> : null}
                {rule.statement}
                <span className="ml-1 text-xs text-muted-foreground">({scopeLabel(rule)})</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <form
        method="get"
        aria-label="Filtrar regras"
        className="flex flex-wrap items-end gap-3 rounded-lg border bg-surface p-3"
      >
        {filters.channel !== null ? (
          <input type="hidden" name="channel" value={filters.channel} />
        ) : null}
        <SelectField
          id="filter-type"
          name="type"
          label="Tipo"
          defaultValue={filters.type ?? ''}
          options={[ALL, ...RULE_TYPES.map((t) => ({ value: t, label: RULE_TYPE_LABELS[t] }))]}
        />
        <SelectField
          id="filter-status"
          name="status"
          label="Status"
          defaultValue={filters.status ?? ''}
          options={[ALL, ...RULE_STATUSES.map((s) => ({ value: s, label: RULE_STATUS[s].label }))]}
        />
        <SelectField
          id="filter-scope"
          name="scope"
          label="Escopo"
          defaultValue={filters.scope ?? ''}
          options={[
            ALL,
            { value: 'client', label: 'Cliente' },
            { value: 'channel', label: 'Canal' },
          ]}
        />
        <Button type="submit" variant="secondary">
          Filtrar
        </Button>
      </form>

      <section aria-labelledby="section-rules">
        <h2 id="section-rules" className="mb-3 text-sm font-medium">
          Todas as regras
        </h2>
        {visible.length === 0 ? (
          <EmptyState
            title={filtered ? 'Nada encontrado com esses filtros' : 'Nenhuma regra ainda'}
            description={
              filtered
                ? 'Ajuste os filtros para ver outras regras.'
                : 'Proponha regras com base em fontes do cliente. Elas só valem depois de ativadas.'
            }
          />
        ) : (
          <ul className="flex flex-col gap-2">
            {visible.map((rule) => {
              const source = sourceById.get(rule.source_id);
              const activatable =
                source === undefined || canPromoteFrom('rule', source.trust_level);
              const validity = formatValidity(rule.effective_from, rule.effective_until);
              const superseded =
                rule.supersedes_rule_id === null
                  ? undefined
                  : ruleById.get(rule.supersedes_rule_id);
              return (
                <li
                  key={rule.id}
                  className={
                    rule.status === 'proposed'
                      ? 'rounded-lg border border-dashed border-status-warning bg-status-warning-surface/40 p-3'
                      : 'rounded-lg border bg-surface p-3'
                  }
                >
                  <div className="flex flex-wrap items-center gap-1.5">
                    <StatusBadge tone="neutral">{RULE_TYPE_LABELS[rule.type]}</StatusBadge>
                    <StatusBadge tone={RULE_STATUS[rule.status].tone}>
                      {RULE_STATUS[rule.status].label}
                    </StatusBadge>
                    {rule.subject ? (
                      <span className="text-xs font-medium">Assunto: {rule.subject}</span>
                    ) : null}
                  </div>
                  <p className="mt-2 text-sm">{rule.statement}</p>
                  <p className="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
                    <span>{scopeLabel(rule)}</span>
                    <span>· prioridade {rule.priority.toString()}</span>
                    {validity ? <span>· validade {validity}</span> : null}
                    <span>· fonte: {source?.title ?? 'indisponível'}</span>
                    {source ? (
                      <StatusBadge tone={SOURCE_TRUST[source.trust_level].tone}>
                        {SOURCE_TRUST[source.trust_level].label}
                      </StatusBadge>
                    ) : null}
                  </p>
                  {superseded ? (
                    <p className="mt-1 text-xs text-muted-foreground">
                      Substitui: {superseded.statement}
                    </p>
                  ) : null}
                  {can.activateRules &&
                  (rule.status === 'proposed' || rule.status === 'conflict') ? (
                    <div className="mt-3 flex flex-wrap items-start gap-2">
                      {rule.status === 'proposed' ? (
                        <BrainForm
                          action={reviewRule}
                          hidden={{ ...scope, id: rule.id, decision: 'activate' }}
                          submitLabel="Ativar"
                          pendingLabel="Ativando…"
                          variant="inline"
                          disabled={!activatable}
                        />
                      ) : null}
                      <BrainForm
                        action={reviewRule}
                        hidden={{ ...scope, id: rule.id, decision: 'reject' }}
                        submitLabel="Rejeitar"
                        pendingLabel="Rejeitando…"
                        submitVariant="secondary"
                        variant="inline"
                      />
                      {!activatable ? (
                        <p className="text-xs text-muted-foreground">
                          Fonte externa não confiável: esta regra não pode ser ativada.
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
        <section
          aria-labelledby="section-propose-rule"
          className="rounded-lg border bg-surface p-4"
        >
          <h2 id="section-propose-rule" className="text-sm font-medium">
            Propor regra
          </h2>
          {sources.length === 0 ? (
            <p className="mt-2 text-sm text-muted-foreground">
              Registre uma fonte em Conhecimento antes: toda regra precisa de proveniência.
            </p>
          ) : (
            <BrainForm
              action={proposeRule}
              hidden={scope}
              submitLabel="Propor regra"
              pendingLabel="Enviando…"
              resetOnSuccess
              className="mt-3 max-w-2xl"
            >
              <div className="grid gap-3 sm:grid-cols-2">
                <SelectField
                  id="rule-type"
                  name="type"
                  label="Tipo"
                  options={RULE_TYPES.map((t) => ({ value: t, label: RULE_TYPE_LABELS[t] }))}
                />
                <SelectField
                  id="rule-source"
                  name="sourceId"
                  label="Fonte"
                  options={sources.map((s) => ({
                    value: s.id,
                    label: `${s.title} (${SOURCE_TRUST[s.trust_level].label})`,
                  }))}
                />
                <TextField
                  id="rule-subject"
                  name="subject"
                  label="Assunto (obrigatório para MUST e MUST NOT)"
                  list="rule-subjects"
                  maxLength={80}
                />
                <datalist id="rule-subjects">
                  {subjects.map((subject) => (
                    <option key={subject} value={subject} />
                  ))}
                </datalist>
                <TextField
                  id="rule-channel"
                  name="channel"
                  label="Canal (vazio = todos)"
                  placeholder="instagram"
                  maxLength={40}
                />
              </div>
              <TextAreaField
                id="rule-statement"
                name="statement"
                label="Regra"
                required
                maxLength={2000}
              />
              <div className="grid gap-3 sm:grid-cols-3">
                <TextField
                  id="rule-priority"
                  name="priority"
                  type="number"
                  min={0}
                  max={100}
                  step={1}
                  defaultValue={50}
                  label="Prioridade (0–100)"
                />
                <TextField
                  id="rule-from"
                  name="effectiveFrom"
                  type="date"
                  label="Vale a partir de"
                />
                <TextField
                  id="rule-until"
                  name="effectiveUntil"
                  type="date"
                  label="Vale até (exclusivo)"
                />
              </div>
              <SelectField
                id="rule-supersedes"
                name="supersedesRuleId"
                label="Substitui a regra"
                options={[
                  { value: '', label: 'Nenhuma' },
                  ...supersedable.map((rule) => ({
                    value: rule.id,
                    label: `${rule.subject ? `[${rule.subject}] ` : ''}${rule.statement}`.slice(
                      0,
                      120,
                    ),
                  })),
                ]}
              />
            </BrainForm>
          )}
        </section>
      ) : null}
    </div>
  );
}
