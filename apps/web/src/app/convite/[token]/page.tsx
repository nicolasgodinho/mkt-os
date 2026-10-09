import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { TextField } from '@jmos/ui';
import { ActionForm } from '@/components/action-form';
import { acceptInvitation, sendAccessLink } from '@/lib/admin/actions';
import { TOKEN } from '@/lib/admin/model';
import { getSessionUser } from '@/lib/auth/session';
import { getSupabaseConfig } from '@/lib/supabase/config';

export const metadata: Metadata = { title: 'Convite' };

/**
 * Invitation link (Increment 9, ADR 0005). A signed-in person accepts it; someone new creates an
 * account with the invited e-mail first. The page reveals nothing about the invitation: the
 * database validates the token and the e-mail on acceptance.
 */
export default async function InvitationPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!TOKEN.test(token)) notFound();
  const user = await getSessionUser();
  const here = `/convite/${token}`;

  return (
    <main
      id="main"
      className="mx-auto flex min-h-dvh w-full max-w-sm flex-col justify-center px-4 py-10"
    >
      <div className="mb-6">
        <p className="text-sm font-semibold">Jansen Marketing OS</p>
        <h1 className="mt-1 text-xl font-semibold tracking-tight">Convite</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Você foi convidado para acessar o Jansen Marketing OS.
        </p>
      </div>

      {getSupabaseConfig() === null ? (
        <p
          role="alert"
          className="rounded-md border bg-surface px-3 py-2 text-sm text-status-warning"
        >
          A autenticação não está configurada neste ambiente.
        </p>
      ) : user === null ? (
        <>
          <section aria-labelledby="create-account">
            <h2 id="create-account" className="text-sm font-medium">
              Acesso
            </h2>
            <p className="mt-1 text-xs text-muted-foreground">
              Digite o e-mail que recebeu o convite para receber um link de acesso.
            </p>
            <ActionForm
              action={sendAccessLink}
              hidden={{ token }}
              buttons={[{ label: 'Receber link de acesso' }]}
              pendingLabel="Enviando…"
              className="mt-3"
            >
              <TextField
                id="signup-email"
                name="email"
                type="email"
                label="E-mail"
                autoComplete="email"
                required
              />
            </ActionForm>
          </section>
          <p className="mt-6 text-sm">
            Já tem conta?{' '}
            <Link href={`/login?next=${encodeURIComponent(here)}`} className="text-primary">
              Entre com senha e volte a este link
            </Link>
          </p>
        </>
      ) : (
        <section aria-labelledby="accept">
          <h2 id="accept" className="text-sm font-medium">
            Aceitar convite
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            O convite precisa ter sido feito para o e-mail desta conta.
          </p>
          <ActionForm
            action={acceptInvitation}
            hidden={{ token }}
            buttons={[{ label: 'Aceitar convite' }]}
            pendingLabel="Aceitando…"
            className="mt-3"
          />
        </section>
      )}
    </main>
  );
}
