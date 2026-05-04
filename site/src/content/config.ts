import { defineCollection, z } from 'astro:content';

export const KIT_SLUGS = [
  'speckit',
  'swarmkit',
  'squadkit',
  'polishkit',
  'flowkit',
  'sessionkit',
  'vaultkit',
  'general',
] as const;

export const TAG_VOCAB = [
  'how-to',
  'tutorial',
  'workflow',
  'deep-dive',
  'release',
  'announcement',
  'tips',
  'case-study',
] as const;

const posts = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    subtitle: z.string().optional(),
    kit: z.enum(KIT_SLUGS).optional(),
    date: z.coerce.date(),
    author: z.string().default('smallorbit'),
    heroImage: z.string().optional(),
    ogImage: z.string().optional(),
    readTime: z.number().optional(),
    draft: z.boolean().default(false),
    tags: z.array(z.enum(TAG_VOCAB)).max(5).default([]),
  }),
});

// Astro 5 reserves `slug` in `type: 'content'` collections (auto-derived from
// the entry filename and exposed as `entry.id`). Consumers route on `entry.id`.
const kits = defineCollection({
  type: 'content',
  schema: z.object({
    name: z.string(),
    role: z.string(),
    oneLiner: z.string(),
    commands: z.array(z.string()).default([]),
    summary: z.string(),
  }),
});

const transcriptSegment = z.object({
  type: z.enum(['prompt', 'cmd', 'annotate', 'text']),
  text: z.string(),
});

const transcripts = defineCollection({
  type: 'data',
  schema: z.object({
    ariaLabel: z.string(),
    lines: z.array(z.array(transcriptSegment)),
  }),
});

export const collections = { posts, kits, transcripts };
