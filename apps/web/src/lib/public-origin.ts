const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]']);

/**
 * The public origin used in invitation and e-mail links. It comes only from JMOS_PUBLIC_URL, never from
 * request headers (ADR 0005). Outside development it must be https, except a loopback address used to
 * run the production build locally or in CI.
 */
export function publicOrigin(): string {
  const value = process.env.JMOS_PUBLIC_URL;
  if (!value) {
    if (process.env.NODE_ENV === 'development') return 'http://127.0.0.1:3000';
    throw new Error('Missing JMOS_PUBLIC_URL configuration (required in production).');
  }
  if (!URL.canParse(value)) {
    throw new Error('Invalid JMOS_PUBLIC_URL configuration. Must be a valid URL.');
  }
  const url = new URL(value);
  const secure =
    url.protocol === 'https:' || (url.protocol === 'http:' && LOOPBACK_HOSTS.has(url.hostname));
  if (process.env.NODE_ENV !== 'development' && !secure) {
    throw new Error('JMOS_PUBLIC_URL must be an https origin in production.');
  }
  return url.origin;
}
