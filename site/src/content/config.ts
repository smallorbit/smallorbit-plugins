import { defineCollection, z } from 'astro:content';

const posts = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    subtitle: z.string().optional(),
    kit: z.string().optional(),
    date: z.coerce.date(),
    author: z.string().default('smallorbit'),
    heroImage: z.string().optional(),
    ogImage: z.string().optional(),
    readTime: z.number().optional(),
    draft: z.boolean().default(false),
    tags: z.array(z.string()).default([]),
  }),
});

const kits = defineCollection({
  type: 'content',
  schema: z.object({
    name: z.string(),
    role: z.string(),
    accentColor: z.string(),
    oneLiner: z.string(),
    commands: z.array(z.string()).default([]),
    summary: z.string(),
  }),
});

export const collections = { posts, kits };
