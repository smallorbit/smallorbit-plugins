# smallorbit-plugins site

Astro project that powers the public landing and blog at
<https://smallorbit.github.io/smallorbit-plugins/>.

## Local development

```bash
cd site
npm install
npm run dev      # http://localhost:4321
```

## Build

```bash
npm run build    # produces site/dist/
npm run preview  # serves the built site locally
```

## Production deploy

Production deploys are automated. The `.github/workflows/deploy-site.yml`
workflow builds this project on every push to `develop` and `main`, then
publishes the `dist/` output to the `gh-pages` branch via
`peaceiris/actions-gh-pages`.

GitHub Pages is configured to serve from the `gh-pages` branch root —
do not enable per-folder Pages serving for `docs/` once the cutover lands.

## Layout

- `src/pages/` — Astro routes.
- `src/layouts/BaseLayout.astro` — site-wide HTML shell, meta tags, header
  nav, footer, and light-theme CSS custom properties.
- `src/styles/` — global stylesheets.
- `src/content/` — content collections for `posts`, `kits`, and `transcripts`.
