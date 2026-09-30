/**
 * Liveness check for the web app. It deliberately does not probe the AI Worker:
 * the portal must stay available when the local GPU worker is offline (docs/00 principle 7).
 */
export const dynamic = 'force-dynamic';

export function GET(): Response {
  return Response.json(
    { status: 'ok', service: 'web', time: new Date().toISOString() },
    { headers: { 'Cache-Control': 'no-store' } },
  );
}
