import { z } from 'zod';

/** The capability contract of docs/01, as stored in the database enum `public.capability`. */
export const CAPABILITIES = [
  'workspace.manage',
  'client.manage',
  'client.view',
  'strategy.edit',
  'knowledge.propose',
  'knowledge.approve',
  'rule.activate',
  'content.create',
  'content.edit',
  'content.review_internal',
  'approval.request',
  'approval.decide',
  'publication.schedule',
  'publication.publish',
  'request.submit',
  'request.triage',
  'project.manage',
  'integration.manage',
  'audit.view',
  'admin.support',
] as const;

export type Capability = (typeof CAPABILITIES)[number];

export const capabilityListSchema = z.array(z.enum(CAPABILITIES));

/** pt-BR labels shown to users. Authorization is always decided by the database. */
export const CAPABILITY_LABELS: Record<Capability, string> = {
  'workspace.manage': 'Administrar o workspace',
  'client.manage': 'Gerenciar clientes',
  'client.view': 'Visualizar cliente',
  'strategy.edit': 'Editar estratégia',
  'knowledge.propose': 'Propor conhecimento',
  'knowledge.approve': 'Aprovar conhecimento',
  'rule.activate': 'Ativar regras',
  'content.create': 'Criar conteúdo',
  'content.edit': 'Editar conteúdo',
  'content.review_internal': 'Revisão interna de conteúdo',
  'approval.request': 'Solicitar aprovação',
  'approval.decide': 'Aprovar materiais',
  'publication.schedule': 'Agendar publicações',
  'publication.publish': 'Publicar',
  'request.submit': 'Enviar solicitações',
  'request.triage': 'Triar solicitações',
  'project.manage': 'Gerenciar projetos',
  'integration.manage': 'Gerenciar integrações',
  'audit.view': 'Ver auditoria',
  'admin.support': 'Suporte administrativo',
};

export interface PortalArea {
  key: 'content' | 'approvals' | 'requests';
  label: string;
  description: string;
}

/**
 * Client Portal areas a client-side member may use, derived from capabilities (docs/06 portal
 * navigation). The modules themselves arrive in later increments.
 */
export function portalAreasFor(capabilities: readonly Capability[]): PortalArea[] {
  const areas: PortalArea[] = [];
  if (capabilities.includes('client.view')) {
    areas.push({
      key: 'content',
      label: 'Conteúdo e calendário',
      description: 'Acompanhar o que está em produção e o que será publicado.',
    });
  }
  if (capabilities.includes('approval.decide')) {
    areas.push({
      key: 'approvals',
      label: 'Aprovações',
      description: 'Aprovar materiais ou pedir ajustes.',
    });
  }
  if (capabilities.includes('request.submit')) {
    areas.push({
      key: 'requests',
      label: 'Solicitações',
      description: 'Enviar novas demandas para a equipe.',
    });
  }
  return areas;
}
