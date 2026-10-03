import type { Metadata, Viewport } from 'next';
import { headers } from 'next/headers';
import type { ReactNode } from 'react';
import './globals.css';

export const metadata: Metadata = {
  title: { default: 'Jansen Marketing OS', template: '%s · Jansen Marketing OS' },
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
};

export default async function RootLayout({ children }: { children: ReactNode }) {
  // Reading the request headers renders every page per request, which the nonce-based CSP needs
  // (a prerendered page would carry scripts without this request's nonce; see src/proxy.ts).
  await headers();
  return (
    <html lang="pt-BR">
      <body>{children}</body>
    </html>
  );
}
