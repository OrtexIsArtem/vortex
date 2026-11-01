# Vortex website

The landing page at https://vortex-notch.web.app: a static Astro site, in English at `/` and in seven more languages under their own paths. No analytics, no cookies, no requests to other servers.

- `npm ci`, then `npm run dev` for http://localhost:4321.
- Before a change: `npm run check` and `npm test`.
- `SITE_URL=https://vortex-notch.web.app npm run build` writes `dist/`. Without `SITE_URL`, links for search engines and social previews are relative, and a build on CI stops.
- Words: `src/copy/<language>.ts`, shaped like the English one (`src/copy/types.ts`). The app's own words stay English on languages the app doesn't speak.
- Social preview and icons: `node og/render.mjs` redraws them from `og/` with Google Chrome.
- Deploy: `.github/workflows/site.yml` checks and builds every change to `site/`. A pull request gets a preview link; `main` goes live on Firebase Hosting (`firebase.json`).
