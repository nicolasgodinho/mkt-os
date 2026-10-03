import { describe, expect, it } from 'vitest';
import { buildCsp, createNonce } from './csp';

function directives(policy: string): Map<string, string> {
  return new Map(
    policy.split('; ').map((part) => {
      const [name = '', ...values] = part.split(' ');
      return [name, values.join(' ')];
    }),
  );
}

describe('buildCsp', () => {
  it('lets only nonce-tagged scripts run in production', () => {
    const policy = directives(
      buildCsp({ nonce: 'abc', supabaseUrl: 'https://xyz.supabase.co/', development: false }),
    );
    expect(policy.get('script-src')).toBe("'self' 'nonce-abc' 'strict-dynamic'");
    expect(policy.get('connect-src')).toBe("'self' https://xyz.supabase.co");
    expect(policy.get('frame-ancestors')).toBe("'none'");
    expect(policy.get('object-src')).toBe("'none'");
    expect(policy.get('base-uri')).toBe("'self'");
    expect(policy.get('form-action')).toBe("'self'");
  });

  it('allows what Next.js development needs, only in development', () => {
    const policy = directives(buildCsp({ nonce: 'n', supabaseUrl: null, development: true }));
    expect(policy.get('script-src')).toContain("'unsafe-eval'");
    expect(policy.get('connect-src')).toBe("'self' ws:");
  });

  it('ignores a malformed Supabase URL instead of breaking the policy', () => {
    const policy = directives(
      buildCsp({ nonce: 'n', supabaseUrl: 'not a url', development: false }),
    );
    expect(policy.get('connect-src')).toBe("'self'");
  });
});

describe('createNonce', () => {
  it('returns 128 random bits as base64, different each time', () => {
    const first = createNonce();
    expect(first).toMatch(/^[A-Za-z0-9+/]{22}==$/);
    expect(createNonce()).not.toBe(first);
  });
});
