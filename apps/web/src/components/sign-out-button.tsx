import { LogOut } from 'lucide-react';
import { Button } from '@jmos/ui';
import { signOut } from '@/lib/auth/actions';

/** Sign-out is a POST (server action), never a GET link that could be triggered cross-site. */
export function SignOutButton({ compact = false }: { compact?: boolean }) {
  return (
    <form action={signOut}>
      <Button type="submit" variant={compact ? 'ghost' : 'secondary'}>
        <LogOut aria-hidden className="size-4" />
        Sair
      </Button>
    </form>
  );
}
