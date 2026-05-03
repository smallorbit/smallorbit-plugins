---
title: "Welcome to the smallorbit blog"
subtitle: "What we're building, why it matters, and how the kits fit together"
kit: flowkit
date: 2026-05-03
author: smallorbit
readTime: 6
draft: false
tags: ["meta", "announcement"]
---

This is the seed post for the smallorbit blog &mdash; equal parts welcome mat and
typography test. It walks through every component the reading layout supports so
the design can be verified against a real piece of writing.

## Why a blog?

We ship Claude Code plugins that sit at the intersection of planning, parallel
execution, and release discipline. The kits make sense in motion, not in a feature
matrix &mdash; so we needed somewhere to show the work. That's what this lives for.

The reading experience is intentionally Substack-flavored: a generous measure, a
serif title, and a body that gets out of the way.

<aside class="callout" style="--callout-accent: var(--flowkit, var(--color-accent));">
  <div class="callout__body">
    <p>The reading layout is the visible payoff of Phase 0 design work. If it lands
    flat, the whole content effort lands flat.</p>
  </div>
</aside>

## Code blocks

Fenced code blocks are highlighted with the `github-light` Shiki theme so they
sit comfortably against the warm-paper background. Inline `code` fragments use a
chip with a subtle border.

```ts
import { defineCollection, z } from 'astro:content';

const posts = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    date: z.coerce.date(),
    readTime: z.number().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { posts };
```

```bash
# Create a feature branch and start a swarm
flowkit cut-epic blog 775
swarmkit swarm --epic blog-775
```

### Inline code

Try a sentence with a few inline references &mdash; for instance, calling
`getCollection('posts')` and then awaiting `entry.render()` to get a renderable
`<Content />` component.

## Captioned images

<figure class="figure">
  <img
    src="https://placehold.co/1200x600/ede9e3/737069/png?text=smallorbit"
    alt="Placeholder hero illustration for the smallorbit blog"
    loading="lazy"
    decoding="async"
  />
  <figcaption class="figure__caption">
    A captioned image &mdash; the workhorse of any essay format.
  </figcaption>
</figure>

## Pull quotes

> The kits make sense in motion, not in a feature matrix.

The default markdown blockquote inherits the post's accent color via
`--post-accent`, so a pillar post tagged `kit: flowkit` gets a flowkit-blue
left border without any per-post styling.

## Audio voiceover

The audio voiceover slot lives at the top of every post, just under the byline.
When a post has no recorded audio yet, the slot stays collapsed with a placeholder
&mdash; no missing-asset clutter. We will wire up real audio sources once the
production pipeline is ready.

## Wrap

That's the seed. Subsequent posts can lean on the same components without thinking
about layout: drop the markdown in, fill in `kit:` and `readTime:` in the
frontmatter, and the rest follows.
