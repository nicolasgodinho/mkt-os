import { StatusBadge } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { revokeInvitation } from '@/lib/admin/actions';
import {
  CLIENT_ROLE_LABELS,
  isOpen,
  WORKSPACE_ROLE_LABELS,
  type Invitation,
} from '@/lib/admin/model';
import { CAPABILITY_LABELS } from '@/lib/identity/capabilities';
import { formatDateTime } from '@/lib/jobs/model';

const STATUS = {
  pending: { label: 'Aguardando', tone: 'info' },
  accepted: { label: 'Aceito', tone: 'success' },
  revoked: { label: 'Revogado', tone: 'neutral' },
  expired: { label: 'Expirado', tone: 'neutral' },
} as const;

/** Invitations of one target, newest first; open ones can be revoked. */
export function InvitationList({
  invitations,
  scope,
  now,
}: {
  invitations: readonly Invitation[];
  scope: { workspaceSlug: string; workspaceId: string; clientId?: string };
  now: Date;
}) {
  if (invitations.length === 0) {
    return <p className="text-sm text-muted-foreground">Nenhum convite ainda.</p>;
  }
  return (
    <ul className="flex flex-col gap-2" aria-label="Convites">
      {invitations.map((invitation) => {
        const open = isOpen(invitation, now);
        const status =
          open || invitation.status !== 'pending' ? STATUS[invitation.status] : STATUS.expired;
        const role =
          invitation.workspace_role === null
            ? invitation.client_role === null
              ? ''
              : CLIENT_ROLE_LABELS[invitation.client_role]
            : WORKSPACE_ROLE_LABELS[invitation.workspace_role];
        return (
          <li key={invitation.id} className="rounded-lg border bg-surface p-3 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-medium break-all">{invitation.email}</span>
              <StatusBadge tone={status.tone}>{status.label}</StatusBadge>
              <span className="text-xs text-muted-foreground">
                {role}
                {invitation.capabilities.length > 0
                  ? ` + ${invitation.capabilities.map((c) => CAPABILITY_LABELS[c]).join(', ')}`
                  : ''}
                {open ? ` · expira em ${formatDateTime(invitation.expires_at) ?? ''}` : ''}
              </span>
            </div>
            {open ? (
              <ActionForm
                action={revokeInvitation}
                hidden={{
                  workspaceSlug: scope.workspaceSlug,
                  workspaceId: scope.workspaceId,
                  invitationId: invitation.id,
                  ...(scope.clientId === undefined ? {} : { clientId: scope.clientId }),
                }}
                buttons={[
                  {
                    label: 'Revogar convite',
                    ariaLabel: `Revogar convite de ${invitation.email}`,
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
  );
}
