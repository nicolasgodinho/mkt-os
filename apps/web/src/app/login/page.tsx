import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { getSessionUser } from '@/lib/auth/session';
import { safeNextPath } from '@/lib/identity/routing';
import { getSupabaseConfig } from '@/lib/supabase/config';
import { LoginForm } from './login-form';

export const metadata: Metadata = { title: 'Entrar' };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { next } = await searchParams;
  const nextPath = safeNextPath(next);
  if ((await getSessionUser()) !== null) redirect(nextPath);

  return (
    <main
      id="main"
      className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center px-4 py-10"
    >
      <div className="mb-6">
        <p className="text-sm font-semibold">Jansen Marketing OS</p>
        <h1 className="mt-1 text-xl font-semibold tracking-tight">Entrar</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Acesso para a equipe Jansen e para clientes.
        </p>
      </div>
      {getSupabaseConfig() === null ? (
        <p
          role="alert"
          className="rounded-md border bg-surface px-3 py-2 text-sm text-status-warning"
        >
          A autenticação não está configurada neste ambiente.
        </p>
      ) : (
        <LoginForm nextPath={nextPath} />
      )}
    </main>
  );
}
