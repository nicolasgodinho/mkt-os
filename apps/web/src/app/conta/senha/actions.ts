'use server';

import { redirect } from 'next/navigation';
import { z } from 'zod';
import type { ActionState } from '@/lib/action-state';
import { createSupabaseWriter } from '@/lib/supabase/server';

const passwordSchema = z.object({
  password: z.string().min(12).max(200),
  next: z.string().default('/'),
});

export async function updatePassword(_p: ActionState, formData: FormData): Promise<ActionState> {
  const result = passwordSchema.safeParse(Object.fromEntries(formData.entries()));
  if (!result.success) {
    return { status: 'error', message: 'A senha deve ter pelo menos 12 caracteres.' };
  }
  const { password, next } = result.data;

  // Validate `next` is a same-origin relative path
  const isValidNext = next.startsWith('/') && !next.startsWith('//') && !next.includes('\\');
  const redirectTarget = isValidNext ? next : '/';

  const supabase = await createSupabaseWriter();
  if (supabase === null) {
    return { status: 'error', message: 'Configuração de autenticação ausente.' };
  }

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    return { status: 'error', message: 'Não foi possível atualizar a senha. Tente novamente.' };
  }

  redirect(redirectTarget);
}
