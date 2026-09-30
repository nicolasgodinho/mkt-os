import {
  CalendarDays,
  ChartColumn,
  ChartLine,
  CircleCheck,
  FileText,
  Flag,
  Folder,
  FolderOpen,
  House,
  Inbox,
  Lightbulb,
  MessageSquarePlus,
  Settings,
  Users,
  Video,
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

/** Internal global navigation (docs/06 "Internal global navigation"). */
export const internalNavigation: readonly NavItem[] = [
  { href: '/', label: 'Início', icon: House, available: true },
  { href: '/inbox', label: 'Caixa de entrada', icon: Inbox, available: false },
  { href: '/clients', label: 'Clientes', icon: Users, available: false },
  { href: '/calendar', label: 'Calendário', icon: CalendarDays, available: false },
  { href: '/initiatives', label: 'Campanhas / Iniciativas', icon: Flag, available: false },
  { href: '/content', label: 'Conteúdo', icon: FileText, available: false },
  { href: '/approvals', label: 'Aprovações', icon: CircleCheck, available: false },
  { href: '/requests', label: 'Solicitações', icon: MessageSquarePlus, available: false },
  { href: '/intelligence', label: 'Inteligência', icon: Lightbulb, available: false },
  { href: '/analytics', label: 'Analytics', icon: ChartColumn, available: false },
  { href: '/assets', label: 'Ativos', icon: FolderOpen, available: false },
  { href: '/automations', label: 'Automações', icon: Workflow, available: false },
  { href: '/settings', label: 'Configurações', icon: Settings, available: false },
];

/**
 * Client Portal navigation (docs/06 "Client Portal navigation").
 * Unavailable modules are hidden from clients rather than teased.
 */
export const portalNavigation: readonly NavItem[] = [
  { href: '/portal', label: 'Início', icon: House, available: true },
  { href: '/portal/calendar', label: 'Calendário', icon: CalendarDays, available: false },
  { href: '/portal/approvals', label: 'Aprovações', icon: CircleCheck, available: false },
  { href: '/portal/requests', label: 'Solicitações', icon: MessageSquarePlus, available: false },
  { href: '/portal/content', label: 'Conteúdo', icon: FileText, available: false },
  { href: '/portal/results', label: 'Resultados', icon: ChartLine, available: false },
  { href: '/portal/files', label: 'Arquivos', icon: Folder, available: false },
  { href: '/portal/meetings', label: 'Reuniões', icon: Video, available: false },
];
