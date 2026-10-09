import Link from 'next/link';
import type { Workspace } from '@/lib/identity/queries';
import type { Capability } from '@/lib/identity/capabilities';
import { internalNavigation } from '@/navigation';
import { SignOutButton } from './sign-out-button';

/** Small-screen bar for the desktop-first internal shell: available modules and sign-out. */
export function InternalCompactNavigation({
  workspace,
  capabilities,
}: {
  workspace: Workspace;
  capabilities: readonly Capability[];
}) {
  const available = internalNavigation(workspace.slug, capabilities).filter(
    (item) => item.available,
  );
  return (
    <div className="flex items-center justify-between gap-3">
      <div className="min-w-0">
        <p className="truncate text-sm font-semibold">{workspace.name}</p>
        <nav aria-label="Navegação compacta" className="flex gap-3">
          {available.map((item) => (
            <Link key={item.href} href={item.href} className="text-xs text-muted-foreground">
              {item.label}
            </Link>
          ))}
        </nav>
      </div>
      <SignOutButton compact />
    </div>
  );
}
