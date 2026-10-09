export function safeNextPath(next: string | null, origin: string): string {
  if (!next) return '/';
  // Reject control characters including tab, CR, LF
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(next)) return '/';

  try {
    const url = new URL(next, origin);
    if (url.origin !== origin) return '/';
    return url.pathname + url.search;
  } catch {
    return '/';
  }
}
