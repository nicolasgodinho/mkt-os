import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { getSessionUser } from '@/lib/auth/session';
import { updatePassword } from './actions';

export const metadata: Metadata = { title: 'Definir Senha' };

export default async function SetPasswordPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const user = await getSessionUser();
  if (user === null) {
    redirect('/login');
  }

  const { next } = await searchParams;

  return (
    <main
      id="main"
      className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center px-4 py-10"
    >
      <div className="mb-6">
        <h1 className="mt-1 text-xl font-semibold tracking-tight">Definir Senha</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Defina uma senha para entrar sem link de e-mail na próxima vez.
        </p>
      </div>

      <ActionForm
        action={updatePassword}
        hidden={{ next: next ?? '/' }}
        buttons={[{ label: 'Salvar senha' }]}
        pendingLabel="Salvando…"
      >
        <TextField
          id="password"
          name="password"
          type="password"
          label="Nova senha (mínimo 12 caracteres)"
          autoComplete="new-password"
          minLength={12}
          required
        />
      </ActionForm>
    </main>
  );
}
