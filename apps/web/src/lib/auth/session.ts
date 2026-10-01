import 'server-only';
import { redirect } from 'next/navigation';
import { cache } from 'react';
import { createSupabaseReader } from '@/lib/supabase/server';

export interface SessionUser {
  id: string;
  email: string | null;
}

/**
 * The signed-in user, validated with Supabase Auth (not just decoded from the cookie).
 * Null when there is no valid session or authentication is not configured.
 */
export const getSessionUser = cache(async (): Promise<SessionUser | null> => {
  const supabase = await createSupabaseReader();
  if (supabase === null) return null;
  const { data, error } = await supabase.auth.getUser();
  // "No session" is an expected answer here; any other error is treated the same way (deny).
  if (error !== null) return null;
  return { id: data.user.id, email: data.user.email ?? null };
});

/** Redirects to the login page unless there is a valid session. */
export async function requireSessionUser(returnTo: string): Promise<SessionUser> {
  const user = await getSessionUser();
  if (user === null) redirect(`/login?next=${encodeURIComponent(returnTo)}`);
  return user;
}
