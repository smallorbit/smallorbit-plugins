import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';

export default defineConfig({
  site: 'https://smallorbit.github.io',
  base: '/smallorbit-plugins',
  output: 'static',
  trailingSlash: 'always',
  markdown: {
    shikiConfig: {
      theme: 'github-light',
      wrap: false,
    },
  },
  integrations: [mdx()],
});
