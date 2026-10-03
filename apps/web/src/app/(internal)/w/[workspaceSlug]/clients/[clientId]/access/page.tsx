import type { Metadata } from 'next';
import Link from 'next/link';
import { EmptyState, PageHeader, SelectField, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { CapabilityCheckboxes } from '@/components/admin/capability-checkboxes';
import { InvitationList } from '@/components/admin/invitation-list';
import { inviteClientMember, revokeClientMember } from '@/lib/admin/actions';
import { requireClientAdmin } from '@/lib/admin/context';
import {
  CLIENT_ROLE_LABELS,
  CLIENT_ROLES,
  GRANTABLE_CLIENT,
  MEMBERSHIP_STATUS,
} from '@/lib/admin/model';
import { clientMembers, listInvitations } from '@/lib/admin/queries';
import { CAPABILITY_LABELS } from '@/lib/identity/capabilities';

export const metadata: Metadata = { title: 'Acesso do cliente' };

const ROLE_OPTIONS = CLIENT_ROLES.map((role) => ({ value: role, label: CLIENT_ROLE_LABELS[role] }));

/** Who from the client uses the portal (Increment 9). Needs `client.manage`. */
export default async function ClientAccessPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string; clientId: string }>;
}) {
  const { workspaceSlug, clientId } = await params;
  const { workspace, client } = await requireClientAdmin(
    workspaceSlug,
    clientId,
    `/w/${workspaceSlug}/clients/${clientId}/access`,
  );
  const [members, invitations] = await Promise.all([
    clientMembers(client.id),
    listInvitations({ clientId: client.id }),
  ]);
  const scope = { workspaceSlug: workspace.slug, workspaceId: workspace.id, clientId: client.id };

  return (
    <div className="flex flex-col gap-6">
      <div>
        <nav aria-label="Trilha" className="mb-2 text-xs text-muted-foreground">
          <Link href={`/w/${workspace.slug}/clients`} className="hover:text-foreground">
            Clientes
          </Link>
          <span aria-hidden> / </span>
          <Link
            href={`/w/${workspace.slug}/clients/${client.id}`}
            className="hover:text-foreground"
          >
            {client.name}
          </Link>
        </nav>
        <PageHeader
          title={`Acesso ao portal: ${client.name}`}
          description="Pessoas do cliente que aprovam, comentam ou acompanham pelo portal."
        />
      </div>

      <section aria-labelledby="invite-client" className="rounded-lg border bg-surface p-4">
        <h2 id="invite-client" className="text-sm font-medium">
          Convidar pessoa do cliente
        </h2>
        <ActionForm
          action={inviteClientMember}
          hidden={scope}
          buttons={[{ label: 'Criar convite' }]}
          pendingLabel="Criando…"
          resetOnSuccess
          className="mt-3 max-w-xl"
        >
          <TextField id="client-invite-email" name="email" type="email" label="E-mail" required />
          <SelectField
            id="client-invite-role"
            name="role"
            label="Papel no portal"
            options={ROLE_OPTIONS}
            defaultValue="approver"
          />
          <CapabilityCheckboxes
            id="client-invite-capabilities"
            legend="Permissões extras"
            options={GRANTABLE_CLIENT}
          />
        </ActionForm>
      </section>

      <section aria-labelledby="client-members">
        <h2 id="client-members" className="mb-2 text-sm font-medium">
          Pessoas com acesso
        </h2>
        {members.length === 0 ? (
          <EmptyState title="Ninguém do cliente tem acesso ainda" />
        ) : (
          <ul className="flex flex-col gap-2" aria-label="Pessoas do cliente">
            {members.map((member) => {
              const name = member.email ?? member.display_name;
              return (
                <li key={member.user_id} className="rounded-lg border bg-surface p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium break-all">{name}</span>
                    <StatusBadge tone="info">{CLIENT_ROLE_LABELS[member.role]}</StatusBadge>
                    <StatusBadge tone={MEMBERSHIP_STATUS[member.status].tone}>
                      {MEMBERSHIP_STATUS[member.status].label}
                    </StatusBadge>
                  </div>
                  {member.capabilities.length > 0 ? (
                    <p className="mt-1 text-xs text-muted-foreground">
                      Extras: {member.capabilities.map((c) => CAPABILITY_LABELS[c]).join(', ')}
                    </p>
                  ) : null}
                  {member.status === 'active' ? (
                    <ActionForm
                      action={revokeClientMember}
                      hidden={{ ...scope, userId: member.user_id }}
                      buttons={[
                        {
                          label: 'Revogar acesso',
                          ariaLabel: `Revogar acesso de ${name}`,
                          variant: 'secondary',
                        },
                      ]}
                      variant="inline"
                      className="mt-2"
                    />
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section aria-labelledby="client-invitations">
        <h2 id="client-invitations" className="mb-2 text-sm font-medium">
          Convites
        </h2>
        <InvitationList invitations={invitations} scope={scope} now={new Date()} />
      </section>
    </div>
  );
}
