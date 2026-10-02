import { StatusBadge, TextAreaField, TextField } from '@jmos/ui';
import { archiveContextItem, saveContextItem } from '@/lib/brain/actions';
import { formatValidity, type ContextKind, type Offer } from '@/lib/brain/model';
import { BrainForm } from './brain-form';

interface ContextItem {
  id: string;
  name: string;
  description: string;
  status: 'active' | 'archived';
  valid_from?: Offer['valid_from'];
  valid_until?: Offer['valid_until'];
}

interface ContextSectionProps {
  kind: ContextKind;
  title: string;
  addLabel: string;
  emptyLabel: string;
  items: readonly ContextItem[];
  scope: { workspaceSlug: string; clientId: string };
  canEdit: boolean;
}

function ItemFields({ kind, item }: { kind: ContextKind; item?: ContextItem }) {
  const prefix = `${kind}-${item?.id ?? 'new'}`;
  return (
    <>
      <TextField
        id={`${prefix}-name`}
        name="name"
        label="Nome"
        required
        maxLength={200}
        defaultValue={item?.name}
      />
      <TextAreaField
        id={`${prefix}-description`}
        name="description"
        label="Descrição"
        maxLength={2000}
        defaultValue={item?.description}
      />
      {kind === 'offer' ? (
        <div className="flex flex-col gap-3">
          <TextField
            id={`${prefix}-from`}
            name="validFrom"
            type="date"
            label="Válida a partir de"
            defaultValue={item?.valid_from ?? undefined}
          />
          <TextField
            id={`${prefix}-until`}
            name="validUntil"
            type="date"
            label="Válida até"
            defaultValue={item?.valid_until ?? undefined}
          />
        </div>
      ) : null}
    </>
  );
}

/** Audiences, offers or regions of the client (docs/07 §4). */
export function ContextSection({
  kind,
  title,
  addLabel,
  emptyLabel,
  items,
  scope,
  canEdit,
}: ContextSectionProps) {
  const headingId = `section-${kind}`;
  const active = items.filter((item) => item.status === 'active');
  const archived = items.length - active.length;

  return (
    <section aria-labelledby={headingId} className="rounded-lg border bg-surface p-4">
      <h2 id={headingId} className="text-sm font-medium">
        {title}
      </h2>
      {active.length === 0 ? (
        <p className="mt-3 text-sm text-muted-foreground">{emptyLabel}</p>
      ) : (
        <ul className="mt-3 divide-y">
          {active.map((item) => {
            // Offer dates are inclusive calendar dates (unlike rule and fact windows).
            const validity = formatValidity(
              item.valid_from ?? null,
              item.valid_until ?? null,
              'inclusive',
            );
            return (
              <li key={item.id} className="py-3 first:pt-0">
                <p className="text-sm font-medium">{item.name}</p>
                {item.description ? (
                  <p className="mt-0.5 text-sm text-muted-foreground">{item.description}</p>
                ) : null}
                {validity ? (
                  <p className="mt-1 text-xs text-muted-foreground">Validade: {validity}</p>
                ) : null}
                {canEdit ? (
                  <div className="mt-2 flex flex-wrap items-start gap-3">
                    <details className="text-sm">
                      <summary
                        aria-label={`Editar ${item.name}`}
                        className="cursor-pointer text-xs font-medium text-primary"
                      >
                        Editar
                      </summary>
                      <BrainForm
                        action={saveContextItem}
                        hidden={{ ...scope, kind, id: item.id }}
                        buttons={[{ label: 'Salvar' }]}
                        className="mt-3 max-w-xl"
                      >
                        <ItemFields kind={kind} item={item} />
                      </BrainForm>
                    </details>
                    <BrainForm
                      action={archiveContextItem}
                      hidden={{ ...scope, kind, id: item.id }}
                      buttons={[
                        {
                          label: 'Arquivar',
                          ariaLabel: `Arquivar ${item.name}`,
                          variant: 'ghost',
                        },
                      ]}
                      pendingLabel="Arquivando…"
                      variant="inline"
                    />
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}
      {archived > 0 ? (
        <p className="mt-2 text-xs text-muted-foreground">
          <StatusBadge tone="neutral">{archived.toString()} arquivado(s)</StatusBadge>
        </p>
      ) : null}
      {canEdit ? (
        <details className="mt-4 border-t pt-3">
          <summary className="cursor-pointer text-sm font-medium text-primary">{addLabel}</summary>
          <BrainForm
            action={saveContextItem}
            hidden={{ ...scope, kind }}
            buttons={[{ label: addLabel }]}
            resetOnSuccess
            className="mt-3 max-w-xl"
          >
            <ItemFields kind={kind} />
          </BrainForm>
        </details>
      ) : null}
    </section>
  );
}
