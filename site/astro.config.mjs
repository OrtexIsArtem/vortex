// @ts-check
import { defineConfig } from 'astro/config';

// Where the site lives, given when it is built for hosting: SITE_URL is its origin (https://example.com), BASE_PATH the
// folder when it has one (/vortex). Canonical links, hreflang, the sitemap and social previews need the full address;
// without it they fall back to paths, which serves a preview but not search engines. Host it at the root of a domain
// or subdomain: robots.txt and the site's name and icon in search results work only there.
const site = process.env.SITE_URL || undefined;
const base = process.env.BASE_PATH || undefined;

if (!site && process.argv.includes('build')) {
  // A build on CI is one for hosting, so it stops; a local one only warns.
  const message = '[vortex] SITE_URL is not set: links for search engines and social previews will be relative.';
  if (process.env.CI) throw new Error(message);
  console.warn(message);
}

export default defineConfig({
  site,
  base,
  devToolbar: { enabled: false },
  build: {
    // The CSS is small: inlined, it never blocks the first paint.
    inlineStylesheets: 'always',
  },
  markdown: {
    // The guides' code stays monochrome, as everything on the site is (components/Prose.astro).
    syntaxHighlight: false,
  },
});
