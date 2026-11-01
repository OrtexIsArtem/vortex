# Vortex website

The landing page at https://vortex-notch.web.app and its guides: a static Astro site, in English at `/` and in seven more languages under their own paths. No analytics, no cookies, no requests to other servers.

- `npm ci`, then `npm run dev` for http://localhost:4321.
- Before a change: `npm run check` and `npm test`.
- `SITE_URL=https://vortex-notch.web.app npm run build` writes `dist/`. Without `SITE_URL`, links for search engines and social previews are relative, and a build on CI stops.
- Words: `src/copy/<language>.ts`, shaped like the English one (`src/copy/types.ts`). The app's own words stay English on languages the app doesn't speak.
- Guides: one Markdown file per page and language, `src/content/pages/<language>/<slug>.md`; the frontmatter is checked by `src/content.config.ts`. A page is in English first, at `/<slug>/`; a translation is the same file name under another language's folder, at `/<language>/<slug>/`. The head, hreflang, the language menu, the sitemap, `llms.txt`, the footer's Guides and the landing chapter's link (`chapter:`) follow by themselves. The body starts at `##`; fence code with its language for a Copy button, or as `text` to only show it; link the landing as `../#keys`.
- Social preview and icons: `node og/render.mjs` redraws them from `og/` with Google Chrome.
- Deploy: `.github/workflows/site.yml` checks and builds every change to `site/`. A pull request gets a preview link; `main` goes live on Firebase Hosting (`firebase.json`).
- Download: CI reads the newest published release from GitHub before each build, and publishing a release rebuilds the site, so the button always fetches the latest zip. A local build shows `project.yml`'s version and links to the README's install steps.
