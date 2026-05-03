import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import type { APIContext } from 'astro';

export async function GET(context: APIContext) {
  const allPosts = await getCollection('posts');
  const posts = allPosts
    .filter((entry) => !entry.data.draft)
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());

  const site = context.site!;
  const base = import.meta.env.BASE_URL.endsWith('/')
    ? import.meta.env.BASE_URL
    : `${import.meta.env.BASE_URL}/`;

  return rss({
    title: 'smallorbit blog',
    description:
      'Plan, execute, and ship — Claude Code plugin essays and kit deep-dives from smallorbit.',
    site,
    items: posts.map((entry) => ({
      title: entry.data.title,
      link: `${base}blog/${entry.id.replace(/\.(md|mdx)$/, '')}/`,
      pubDate: entry.data.date,
      description: entry.data.subtitle ?? entry.data.title,
    })),
    customData: '<language>en-us</language>',
  });
}
