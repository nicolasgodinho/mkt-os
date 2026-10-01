import { EmptyState } from '@jmos/ui';
import { SignOutButton } from './sign-out-button';

/** Signed in, but without any active membership: nothing to show, nothing to reveal. */
export function NoAccess({ email }: { email: string | null }) {
  return (
    <main id="main" className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-4 px-4">
      <EmptyState
        title="Sem acesso"
        description="Sua conta ainda não tem acesso a nenhum workspace ou cliente. Peça a um administrador para liberar o acesso."
        action={<SignOutButton />}
      />
      {email ? (
        <p className="text-center text-xs text-muted-foreground">Conectado como {email}</p>
      ) : null}
    </main>
  );
}
