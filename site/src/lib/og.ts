import satori from 'satori';
import { Resvg } from '@resvg/resvg-js';

const KIT_COLORS: Record<string, string> = {
  speckit: '#7c3aed',
  swarmkit: '#166534',
  polishkit: '#b45309',
  flowkit: '#2563eb',
  sessionkit: '#a21caf',
  vaultkit: '#0f766e',
  squadkit: '#be123c',
};

const DEFAULT_ACCENT = '#4f46e5';

let fontDataCache: { fraunces: ArrayBuffer; monaSans: ArrayBuffer } | null = null;

async function loadFonts(): Promise<{ fraunces: ArrayBuffer; monaSans: ArrayBuffer }> {
  if (fontDataCache) return fontDataCache;

  const [frauncesRes, monaSansRes] = await Promise.all([
    fetch(
      'https://fonts.gstatic.com/s/fraunces/v38/6NUh8FyLNQOQZAnv9bYEvDiIdE9Ea92uemAk_WBq8U_9v0c2Wa0K7iN7hzFUPJH58nib1603gg7S2nfgRYIchRujDg.ttf',
    ),
    fetch(
      'https://fonts.gstatic.com/s/monasans/v4/o-0mIpQmx24alC5A4PNB6Ryti20_6n1iPHjcz6L1SoM-jCpoiyAjBN9d.ttf',
    ),
  ]);

  const [fraunces, monaSans] = await Promise.all([
    frauncesRes.arrayBuffer(),
    monaSansRes.arrayBuffer(),
  ]);

  fontDataCache = { fraunces, monaSans };
  return fontDataCache;
}

export interface OgOptions {
  title: string;
  subtitle?: string;
  kit?: string;
}

export async function renderOgPng(options: OgOptions): Promise<ArrayBuffer> {
  const { title, subtitle, kit } = options;
  const accent = kit ? (KIT_COLORS[kit] ?? DEFAULT_ACCENT) : DEFAULT_ACCENT;
  const titleFontSize = title.length > 60 ? 48 : 64;

  const fonts = await loadFonts();

  const contentChildren = [
    {
      type: 'div',
      props: {
        style: {
          fontFamily: 'Mona Sans',
          fontSize: '18px',
          fontWeight: 600,
          color: '#737069',
          marginBottom: '32px',
          letterSpacing: '0.08em',
          textTransform: 'uppercase' as const,
          display: 'flex',
        },
        children: 'smallorbit blog',
      },
    },
    {
      type: 'div',
      props: {
        style: {
          fontFamily: 'Fraunces',
          fontSize: `${titleFontSize}px`,
          fontWeight: 500,
          color: '#1a1612',
          marginBottom: '24px',
          lineHeight: 1.15,
          letterSpacing: '-0.01em',
          flex: '1',
          display: 'flex',
          alignItems: 'flex-start',
        },
        children: title,
      },
    },
    ...(subtitle
      ? [
          {
            type: 'div',
            props: {
              style: {
                fontFamily: 'Fraunces',
                fontSize: '26px',
                fontWeight: 400,
                color: '#737069',
                marginBottom: '40px',
                lineHeight: 1.4,
                display: 'flex',
              },
              children: subtitle,
            },
          },
        ]
      : []),
    {
      type: 'div',
      props: {
        style: {
          display: 'flex',
          flexDirection: 'row' as const,
          alignItems: 'center',
          gap: '12px',
          marginTop: 'auto',
        },
        children: [
          {
            type: 'div',
            props: {
              style: {
                width: '10px',
                height: '10px',
                borderRadius: '50%',
                backgroundColor: accent,
                display: 'flex',
              },
              children: '',
            },
          },
          {
            type: 'div',
            props: {
              style: {
                fontFamily: 'Mona Sans',
                fontSize: '20px',
                fontWeight: 600,
                color: '#2e2a25',
                display: 'flex',
              },
              children: kit ? `smallorbit · ${kit}` : 'smallorbit',
            },
          },
        ],
      },
    },
  ];

  const svg = await satori(
    {
      type: 'div',
      props: {
        style: {
          width: '1200px',
          height: '630px',
          display: 'flex',
          flexDirection: 'row' as const,
          backgroundColor: '#f8f6f1',
        },
        children: [
          {
            type: 'div',
            props: {
              style: {
                width: '8px',
                height: '630px',
                backgroundColor: accent,
                flexShrink: 0,
                display: 'flex',
              },
              children: '',
            },
          },
          {
            type: 'div',
            props: {
              style: {
                display: 'flex',
                flexDirection: 'column' as const,
                flex: '1',
                padding: '64px 64px 64px 56px',
              },
              children: contentChildren,
            },
          },
        ],
      },
    },
    {
      width: 1200,
      height: 630,
      fonts: [
        {
          name: 'Fraunces',
          data: fonts.fraunces,
          weight: 500,
          style: 'normal',
        },
        {
          name: 'Mona Sans',
          data: fonts.monaSans,
          weight: 600,
          style: 'normal',
        },
      ],
    },
  );

  const resvg = new Resvg(svg, {
    fitTo: { mode: 'width', value: 1200 },
  });
  const pngData = resvg.render().asPng();
  return pngData.buffer.slice(
    pngData.byteOffset,
    pngData.byteOffset + pngData.byteLength,
  ) as ArrayBuffer;
}
