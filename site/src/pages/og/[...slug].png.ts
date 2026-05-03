import { getCollection } from 'astro:content';
import { renderOgPng } from '../../lib/og';
import type { APIContext } from 'astro';

export async function getStaticPaths() {
  const allPosts = await getCollection('posts');
  const posts = allPosts.filter((entry) => !entry.data.draft);

  return posts.map((entry) => ({
    params: { slug: entry.id.replace(/\.(md|mdx)$/, '') },
    props: {
      title: entry.data.title,
      subtitle: entry.data.subtitle,
      kit: entry.data.kit,
    },
  }));
}

interface Props {
  title: string;
  subtitle?: string;
  kit?: string;
}

export async function GET({ props }: APIContext<Props>) {
  const png = await renderOgPng({
    title: props.title,
    subtitle: props.subtitle,
    kit: props.kit,
  });

  return new Response(png, {
    headers: {
      'Content-Type': 'image/png',
      'Cache-Control': 'public, max-age=31536000, immutable',
    },
  });
}
