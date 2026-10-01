'use server';

import { redirect } from 'next/navigation';
import { z } from 'zod';
import { safeNextPath } from '@/lib/identity/routing';
import { createSupabaseWriter } from '@/lib/supabase/server';

export interface SignInState {
  error: string | null;
}

const credentialsSchema = z.object({
  email: z.email().max(320),
  password: z.string().min(1).max(200),
});

export async function signIn(_previous: SignInState, formData: FormData): Promise<SignInState> {
  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return { error: 'A autenticação não está configurada neste ambiente.' };
  }
  const parsed = credentialsSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
  });
  if (!parsed.success) return { error: 'Informe um e-mail e uma senha válidos.' };

  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  // One generic message: never reveal whether the e-mail exists.
  if (error !== null) return { error: 'E-mail ou senha incorretos.' };

  redirect(safeNextPath(formData.get('next')));
}

export async function signOut(): Promise<void> {
  const supabase = await createSupabaseWriter();
  if (supabase !== null) {
    const { error } = await supabase.auth.signOut();
    if (error !== null) throw new Error(`sign-out failed (${error.code ?? 'unknown'})`);
  }
  redirect('/login');
}
