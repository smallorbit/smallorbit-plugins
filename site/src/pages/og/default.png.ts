import { renderOgPng } from '../../lib/og';

export async function GET() {
  const png = await renderOgPng({
    title: 'smallorbit blog',
    subtitle: 'Plan, execute, and ship — Claude Code plugin essays and kit deep-dives.',
  });

  return new Response(png, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=31536000, immutable',
    },
  });
}
