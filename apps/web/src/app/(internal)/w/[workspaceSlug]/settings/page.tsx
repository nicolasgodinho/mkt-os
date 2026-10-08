import type { Metadata } from 'next';
import { SelectField, StatusBadge, TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { CapabilityCheckboxes } from '@/components/admin/capability-checkboxes';
import { InvitationList } from '@/components/admin/invitation-list';
import {
  inviteWorkspaceMember,
  revokeWorkspaceMember,
  setWorkspaceMember,
} from '@/lib/admin/actions';
import { requireWorkspaceAdmin } from '@/lib/admin/context';
import {
  GRANTABLE_INTERNAL,
  MEMBERSHIP_STATUS,
  WORKSPACE_ROLE_LABELS,
  WORKSPACE_ROLES,
} from '@/lib/admin/model';
import { listInvitations, workspaceMembers } from '@/lib/admin/queries';
import { CAPABILITY_LABELS } from '@/lib/identity/capabilities';

export const metadata: Metadata = { title: 'Equipe' };

const ROLE_OPTIONS = WORKSPACE_ROLES.map((role) => ({
  value: role,
  label: WORKSPACE_ROLE_LABELS[role],
}));

/** The internal team: members, their access, and invitations (Increment 9). */
export default async function TeamSettingsPage({
  params,
}: {
  params: Promise<{ workspaceSlug: string }>;
}) {
  const { workspaceSlug } = await params;
  const { user, workspace } = await requireWorkspaceAdmin(
    workspaceSlug,
    'workspace.manage',
    `/w/${workspaceSlug}/settings`,
  );
  const [members, invitations] = await Promise.all([
    workspaceMembers(workspace.id),
    listInvitations({ workspaceId: workspace.id }),
  ]);
  const scope = { workspaceSlug: workspace.slug, workspaceId: workspace.id };

  return (
    <div className="flex flex-col gap-6">
      <section aria-labelledby="workspace-id" className="rounded-lg border bg-surface p-4">
        <h2 id="workspace-id" className="text-sm font-medium">
          Identificação do Workspace
        </h2>
        <p className="mt-1 mb-3 text-xs text-muted-foreground">
          Forneça este ID caso seja solicitado pelo suporte técnico.
        </p>
        <div className="max-w-xl">
          <TextField
            id="workspace-id-field"
            name="workspaceId"
            label="ID"
            defaultValue={workspace.id}
            readOnly
          />
        </div>
      </section>

      <section aria-labelledby="invite-member" className="rounded-lg border bg-surface p-4">
        <h2 id="invite-member" className="text-sm font-medium">
          Convidar para a equipe
        </h2>
        <p className="mt-1 text-xs text-muted-foreground">
          O sistema gera um link de convite que você envia para a pessoa. Ela cria a conta com o
          e-mail convidado.
        </p>
        <ActionForm
          action={inviteWorkspaceMember}
          hidden={scope}
          buttons={[{ label: 'Criar convite' }]}
          pendingLabel="Criando…"
          resetOnSuccess
          className="mt-3 max-w-xl"
        >
          <TextField id="invite-email" name="email" type="email" label="E-mail" required />
          <SelectField
            id="invite-role"
            name="role"
            label="Papel"
            options={ROLE_OPTIONS}
            defaultValue="creative"
          />
          <CapabilityCheckboxes
            id="invite-capabilities"
            legend="Permissões extras"
            options={GRANTABLE_INTERNAL}
          />
        </ActionForm>
      </section>

      <section aria-labelledby="members">
        <h2 id="members" className="mb-2 text-sm font-medium">
          Membros
        </h2>
        <ul className="flex flex-col gap-2" aria-label="Membros da equipe">
          {members.map((member) => {
            const name = member.email ?? member.display_name;
            const self = member.user_id === user.id;
            const hidden = { ...scope, userId: member.user_id };
            return (
              <li key={member.user_id} className="rounded-lg border bg-surface p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-medium break-all">{name}</span>
                  {member.display_name && member.display_name !== name ? (
                    <span className="text-xs text-muted-foreground">{member.display_name}</span>
                  ) : null}
                  <StatusBadge tone="info">{WORKSPACE_ROLE_LABELS[member.role]}</StatusBadge>
                  <StatusBadge tone={MEMBERSHIP_STATUS[member.status].tone}>
                    {MEMBERSHIP_STATUS[member.status].label}
                  </StatusBadge>
                  {self ? <span className="text-xs text-muted-foreground">(você)</span> : null}
                </div>
                {member.capabilities.length > 0 ? (
                  <p className="mt-1 text-xs text-muted-foreground">
                    Extras: {member.capabilities.map((c) => CAPABILITY_LABELS[c]).join(', ')}
                  </p>
                ) : null}
                {self ? null : (
                  <details className="mt-2">
                    <summary className="cursor-pointer text-xs text-primary">
                      Alterar acesso
                    </summary>
                    <ActionForm
                      action={setWorkspaceMember}
                      hidden={hidden}
                      buttons={[{ label: 'Salvar acesso', ariaLabel: `Salvar acesso de ${name}` }]}
                      className="mt-2 max-w-xl"
                    >
                      <SelectField
                        id={`role-${member.user_id}`}
                        name="role"
                        label="Papel"
                        options={ROLE_OPTIONS}
                        defaultValue={member.role}
                      />
                      <CapabilityCheckboxes
                        id={`caps-${member.user_id}`}
                        legend="Permissões extras"
                        options={GRANTABLE_INTERNAL}
                        checked={member.capabilities}
                      />
                      {member.capabilities.filter(
                        (c) => !(GRANTABLE_INTERNAL as readonly string[]).includes(c),
                      ).length > 0 && (
                        <div className="mt-2 flex flex-col gap-1">
                          {member.capabilities
                            .filter((c) => !(GRANTABLE_INTERNAL as readonly string[]).includes(c))
                            .map((c) => (
                              <label
                                key={c}
                                className="flex items-center gap-2 text-sm text-muted-foreground opacity-70"
                              >
                                <input type="hidden" name="capabilities" value={c} />
                                <input
                                  type="checkbox"
                                  checked
                                  readOnly
                                  disabled
                                  className="size-4 rounded border-input"
                                />
                                {CAPABILITY_LABELS[c]} (inalterável)
                              </label>
                            ))}
                        </div>
                      )}
                    </ActionForm>
                    {member.status === 'active' ? (
                      <ActionForm
                        action={revokeWorkspaceMember}
                        hidden={hidden}
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
                  </details>
                )}
              </li>
            );
          })}
        </ul>
      </section>

      <section aria-labelledby="invitations">
        <h2 id="invitations" className="mb-2 text-sm font-medium">
          Convites
        </h2>
        <InvitationList invitations={invitations} scope={scope} now={new Date()} />
      </section>
    </div>
  );
}
