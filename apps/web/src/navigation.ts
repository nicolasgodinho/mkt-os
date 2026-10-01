import {
  CalendarDays,
  ChartColumn,
  CircleCheck,
  FileText,
  Flag,
  FolderOpen,
  House,
  Inbox,
  Lightbulb,
  MessageSquarePlus,
  Settings,
  Users,
  Workflow,
  type LucideIcon,
} from 'lucide-react';

export interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  /** Flip to `true` in the increment that ships the module. Never link to a placeholder. */
  available: boolean;
}

/** Internal global navigation (docs/06), scoped to the current workspace. */
export function internalNavigation(workspaceSlug: string): readonly NavItem[] {
  const base = `/w/${workspaceSlug}`;
  return [
    { href: base, label: 'Início', icon: House, available: true },
    { href: `${base}/inbox`, label: 'Caixa de entrada', icon: Inbox, available: false },
    { href: `${base}/clients`, label: 'Clientes', icon: Users, available: true },
    { href: `${base}/calendar`, label: 'Calendário', icon: CalendarDays, available: false },
    { href: `${base}/initiatives`, label: 'Campanhas / Iniciativas', icon: Flag, available: false },
    { href: `${base}/content`, label: 'Conteúdo', icon: FileText, available: false },
    { href: `${base}/approvals`, label: 'Aprovações', icon: CircleCheck, available: false },
    { href: `${base}/requests`, label: 'Solicitações', icon: MessageSquarePlus, available: false },
    { href: `${base}/intelligence`, label: 'Inteligência', icon: Lightbulb, available: false },
    { href: `${base}/analytics`, label: 'Analytics', icon: ChartColumn, available: false },
    { href: `${base}/assets`, label: 'Ativos', icon: FolderOpen, available: false },
    { href: `${base}/automations`, label: 'Automações', icon: Workflow, available: false },
    { href: `${base}/settings`, label: 'Configurações', icon: Settings, available: false },
  ];
}

/**
 * Client Portal navigation (docs/06). Unavailable modules are hidden from clients rather than
 * teased; the portal home lists the areas the member's capabilities allow.
 */
export const portalNavigation: readonly NavItem[] = [
  { href: '/portal', label: 'Início', icon: House, available: true },
];
