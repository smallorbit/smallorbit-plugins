import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://smallorbit.github.io',
  base: '/smallorbit-plugins',
  output: 'static',
  trailingSlash: 'always',
});
