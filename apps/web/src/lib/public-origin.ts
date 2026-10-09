export function publicOrigin(): string {
  const urlString = process.env.JMOS_PUBLIC_URL;
  if (!urlString) {
    if (process.env.NODE_ENV === 'development') {
      return 'http://127.0.0.1:3000';
    }
    throw new Error('Missing JMOS_PUBLIC_URL configuration (required in production).');
  }

  try {
    const url = new URL(urlString);
    if (process.env.NODE_ENV !== 'development' && url.protocol !== 'https:') {
      throw new Error('JMOS_PUBLIC_URL must be a valid https origin in production.');
    }
    return url.origin;
  } catch (err: unknown) {
    if (err instanceof Error && err.message.includes('JMOS_PUBLIC_URL must be')) throw err;
    throw new Error('Invalid JMOS_PUBLIC_URL configuration. Must be a valid URL.', { cause: err });
  }
}
