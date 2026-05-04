import rss from '@astrojs/rss';
import mdxRenderer from '@astrojs/mdx/server.js';
import type { APIContext } from 'astro';
import { experimental_AstroContainer } from 'astro/container';
import { getCollection, type CollectionEntry } from 'astro:content';

import { stripExt } from '../lib/slug';

const URL_ATTR_PATTERN =
  /(<(?:a|img|source|video|audio)\b[^>]*?\s(?:href|src))=("|')([^"']+)\2/gi;
const ABSOLUTE_URL_PATTERN = /^(?:[a-z]+:|\/\/|#|mailto:|tel:|data:)/i;

function absolutizeUrls(html: string, siteOrigin: string, base: string): string {
  const prefix = base.endsWith('/') ? base : `${base}/`;
  const baseNoTrail = prefix.slice(0, -1);
  const origin = siteOrigin.endsWith('/') ? siteOrigin.slice(0, -1) : siteOrigin;

  return html.replace(URL_ATTR_PATTERN, (match, attr: string, quote: string, url: string) => {
    if (ABSOLUTE_URL_PATTERN.test(url)) return match;
    let path: string;
    if (url.startsWith('/')) {
      path = url === baseNoTrail || url.startsWith(`${baseNoTrail}/`) ? url : `${baseNoTrail}${url}`;
    } else {
      path = `${prefix}${url}`;
    }
    return `${attr}=${quote}${origin}${path}${quote}`;
  });
}

type AstroContainer = Awaited<ReturnType<typeof experimental_AstroContainer.create>>;

async function renderPostHtml(
  entry: CollectionEntry<'posts'>,
  container: AstroContainer,
): Promise<string> {
  const { Content } = await entry.render();
  return container.renderToString(Content);
}

export async function GET(context: APIContext): Promise<Response> {
  const allPosts = await getCollection('posts');
  const posts = allPosts
    .filter((entry) => !entry.data.draft)
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());

  const site = context.site!;
  const base = import.meta.env.BASE_URL.endsWith('/')
    ? import.meta.env.BASE_URL
    : `${import.meta.env.BASE_URL}/`;

  const container = await experimental_AstroContainer.create();
  container.addServerRenderer({ renderer: mdxRenderer });

  const items = await Promise.all(
    posts.map(async (entry) => {
      const rawHtml = await renderPostHtml(entry, container);
      const content = absolutizeUrls(rawHtml, site.origin, base);
      return {
        title: entry.data.title,
        link: `${base}blog/${stripExt(entry.id)}/`,
        pubDate: entry.data.date,
        description: entry.data.subtitle ?? entry.data.title,
        content,
      };
    }),
  );

  return rss({
    title: 'smallorbit blog',
    description:
      'Plan, execute, and ship — Claude Code plugin essays and kit deep-dives from smallorbit.',
    site,
    items,
    customData: '<language>en-us</language>',
  });
}
