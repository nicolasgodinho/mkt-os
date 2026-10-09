import { NextResponse } from 'next/server';
import { createSupabaseWriter } from '@/lib/supabase/server';
import { safeNextPath } from '@/lib/auth/safe-redirect';

// E-mail link types this app sends: sign-in links and sign-up confirmations.
const EMAIL_LINK_TYPES = ['email', 'magiclink', 'signup'] as const;

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const token_hash = searchParams.get('token_hash');
  const type = searchParams.get('type');
  const code = searchParams.get('code');

  const redirectTarget = safeNextPath(searchParams.get('next'), origin);

  const supabase = await createSupabaseWriter();
  if (!supabase) {
    return NextResponse.redirect(new URL('/login?erro=link', request.url));
  }

  const otpType = EMAIL_LINK_TYPES.find((allowed) => allowed === type);
  if (token_hash && otpType) {
    const { error } = await supabase.auth.verifyOtp({ token_hash, type: otpType });
    if (!error) {
      return NextResponse.redirect(new URL(redirectTarget, request.url));
    }
  } else if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      return NextResponse.redirect(new URL(redirectTarget, request.url));
    }
  }

  return NextResponse.redirect(new URL('/login?erro=link', request.url));
}
