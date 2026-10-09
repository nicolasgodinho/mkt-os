import { z } from 'zod';
import type { StatusTone } from '@jmos/ui';
import { CAPABILITIES, type Capability } from '../identity/capabilities';

/**
 * Administration contract (tests/acceptance/increment-9/README.md and the Increment 1 identity
 * API) as seen by the web app. Display helpers only: the database decides every change.
 */

export const WORKSPACE_ROLES = [
  'admin',
  'account',
  'strategist',
  'creative',
  'analyst',
  'contributor',
] as const;
export type WorkspaceRole = (typeof WORKSPACE_ROLES)[number];

export const WORKSPACE_ROLE_LABELS: Record<WorkspaceRole, string> = {
  admin: 'Administrador',
  account: 'Atendimento',
  strategist: 'Estrategista',
  creative: 'Criação',
  analyst: 'Analista',
  contributor: 'Colaborador externo',
};

export const CLIENT_ROLES = ['client_admin', 'approver', 'collaborator', 'viewer'] as const;
export type ClientRole = (typeof CLIENT_ROLES)[number];

export const CLIENT_ROLE_LABELS: Record<ClientRole, string> = {
  client_admin: 'Administrador do cliente',
  approver: 'Aprovador',
  collaborator: 'Colaborador',
  viewer: 'Visualizador',
};

/**
 * Capabilities granted on top of a role. High-risk ones are never role defaults (Increment 1),
 * so they are granted here explicitly. `approval.decide` is left out: internal grants never decide
 * client approvals (Increment 6).
 */
export const GRANTABLE_INTERNAL: readonly Capability[] = [
  'client.view',
  'workspace.manage',
  'client.manage',
  'knowledge.approve',
  'rule.activate',
  'approval.request',
  'publication.schedule',
  'publication.publish',
  'integration.manage',
  'audit.view',
];

/** Client-safe extras (a collaborator can be allowed to approve). */
export const GRANTABLE_CLIENT: readonly Capability[] = ['approval.decide', 'request.submit'];

export const MEMBERSHIP_STATUS: Record<
  'invited' | 'active' | 'revoked',
  { label: string; tone: StatusTone }
> = {
  invited: { label: 'Convidado', tone: 'info' },
  active: { label: 'Ativo', tone: 'success' },
  revoked: { label: 'Revogado', tone: 'neutral' },
};

const capabilities = z.array(z.enum(CAPABILITIES));
const membershipStatus = z.enum(['invited', 'active', 'revoked']);

export const workspaceMemberSchema = z.object({
  user_id: z.uuid(),
  display_name: z.string(),
  email: z.string().nullable(),
  role: z.enum(WORKSPACE_ROLES),
  capabilities,
  status: membershipStatus,
});
export type WorkspaceMember = z.infer<typeof workspaceMemberSchema>;

export const clientMemberSchema = workspaceMemberSchema.extend({ role: z.enum(CLIENT_ROLES) });
export type ClientMember = z.infer<typeof clientMemberSchema>;

export const invitationSchema = z.object({
  id: z.uuid(),
  client_id: z.uuid().nullable(),
  email: z.string(),
  workspace_role: z.enum(WORKSPACE_ROLES).nullable(),
  client_role: z.enum(CLIENT_ROLES).nullable(),
  capabilities,
  status: z.enum(['pending', 'accepted', 'revoked', 'expired']),
  expires_at: z.string(),
  created_at: z.string(),
});
export type Invitation = z.infer<typeof invitationSchema>;

/** A pending invitation whose expiry has passed is shown as expired. */
export function isOpen(invitation: Pick<Invitation, 'status' | 'expires_at'>, now: Date): boolean {
  return invitation.status === 'pending' && new Date(invitation.expires_at) > now;
}

/** The link the inviter sends (`/convite/<token>`). */
export function invitationUrl(origin: string, token: string): string {
  return `${origin.replace(/\/+$/, '')}/convite/${token}`;
}

export const TOKEN = /^[0-9a-f]{64}$/;

/** Lowercase words separated by hyphens, as the database requires for client slugs. */
export function slugify(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}
