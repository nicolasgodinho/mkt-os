const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

/** Route ids are validated before any query so malformed input is a plain 404, never an error. */
export function isUuid(value: string): boolean {
  return UUID.test(value);
}

export function isSlug(value: string): boolean {
  return value.length <= 64 && SLUG.test(value);
}

/**
 * Post-login redirect target. Only same-site absolute paths are allowed (no open redirect):
 * protocol-relative (`//evil`), backslash tricks and external URLs fall back to `/`.
 */
export function safeNextPath(value: unknown): string {
  if (typeof value !== 'string' || value === '') return '/';
  if (!value.startsWith('/') || value.startsWith('//') || value.includes('\\')) return '/';
  for (let index = 0; index < value.length; index += 1) {
    if (value.charCodeAt(index) < 0x20) return '/'; // control characters
  }
  try {
    const url = new URL(value, 'http://internal.invalid');
    if (url.origin !== 'http://internal.invalid') return '/';
    return `${url.pathname}${url.search}`;
  } catch {
    // An unparsable target is treated like a missing one.
    return '/';
  }
}
