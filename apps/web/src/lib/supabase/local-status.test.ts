import { describe, expect, it } from 'vitest';
import { parseSupabaseStatusEnv } from './local-status';

const status = [
  'API_URL="http://127.0.0.1:54321"',
  'DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"',
  'ANON_KEY="anon-public"',
  'PUBLISHABLE_KEY="sb_publishable_local"',
  'SERVICE_ROLE_KEY="service-secret"',
  'SECRET_KEY="sb_secret_local"',
  'JWT_SECRET="jwt-secret"',
].join('\n');

describe('parseSupabaseStatusEnv', () => {
  it('returns only the API URL and the public key (publishable preferred)', () => {
    expect(parseSupabaseStatusEnv(status)).toEqual({
      url: 'http://127.0.0.1:54321',
      publicKey: 'sb_publishable_local',
    });
  });

  it('never returns a server-only secret', () => {
    const result = JSON.stringify(parseSupabaseStatusEnv(status));
    for (const secret of ['service-secret', 'sb_secret_local', 'jwt-secret', 'postgres:postgres']) {
      expect(result).not.toContain(secret);
    }
  });

  it('falls back to the legacy anon key', () => {
    expect(parseSupabaseStatusEnv('API_URL=http://localhost:54321\nANON_KEY=anon')).toEqual({
      url: 'http://localhost:54321',
      publicKey: 'anon',
    });
  });

  it('refuses non-local URLs and incomplete output', () => {
    expect(parseSupabaseStatusEnv('API_URL="https://prod.example.com"\nANON_KEY="x"')).toBeNull();
    expect(parseSupabaseStatusEnv('API_URL="http://127.0.0.1:54321"')).toBeNull();
    expect(parseSupabaseStatusEnv('Cannot connect to the Docker daemon')).toBeNull();
  });
});
