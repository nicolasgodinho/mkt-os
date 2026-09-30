'use client';

import { useActionState } from 'react';
import { Button, TextField } from '@jmos/ui';
import { signIn, type SignInState } from '@/lib/auth/actions';

const initialState: SignInState = { error: null };

export function LoginForm({ nextPath }: { nextPath: string }) {
  const [state, action, pending] = useActionState(signIn, initialState);

  return (
    <form action={action} className="flex flex-col gap-4">
      <input type="hidden" name="next" value={nextPath} />
      <TextField
        id="email"
        name="email"
        type="email"
        label="E-mail"
        autoComplete="email"
        required
      />
      <TextField
        id="password"
        name="password"
        type="password"
        label="Senha"
        autoComplete="current-password"
        required
      />
      {state.error !== null ? (
        <p role="alert" className="text-sm text-status-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" disabled={pending}>
        {pending ? 'Entrando…' : 'Entrar'}
      </Button>
    </form>
  );
}
