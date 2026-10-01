'use client';

import { EmptyState, Button } from '@jmos/ui';

/** Generic error boundary: no internals, ids or messages are shown to the user. */
export default function ErrorPage({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main id="main" className="mx-auto flex min-h-dvh max-w-md flex-col justify-center px-4">
      <EmptyState
        title="Algo deu errado"
        description="Não foi possível carregar esta página. Tente novamente em instantes."
        action={
          <Button variant="secondary" onClick={reset}>
            Tentar novamente
          </Button>
        }
      />
    </main>
  );
}
