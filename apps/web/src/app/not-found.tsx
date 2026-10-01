import Link from 'next/link';
import { EmptyState } from '@jmos/ui';

/**
 * Single not-found page for missing AND inaccessible resources, so a guessed id never reveals
 * whether something exists in another tenant (docs/05 §1).
 */
export default function NotFound() {
  return (
    <main id="main" className="mx-auto flex min-h-dvh max-w-md flex-col justify-center px-4">
      <EmptyState
        title="Página não encontrada"
        description="Ela não existe ou você não tem acesso a ela."
        action={
          <Link href="/" className="text-sm font-medium text-primary">
            Voltar ao início
          </Link>
        }
      />
    </main>
  );
}
