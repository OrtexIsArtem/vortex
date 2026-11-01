// Every language's landing, each naming all the others, as the pages' own hreflang links do (layouts/Base.astro); then
// every guide in each language it exists in, naming only those, with the day it last changed.
import type { APIRoute } from 'astro';
import { defaultLocale, localeByCode, locales, urlFor, type LocaleCode } from '../copy/locales';
import { pageGroups } from '../lib/content';
import { absolute, alternatesOf, pagePath } from '../lib/pages';

const link = (hreflang: string, href: string) => `<xhtml:link rel="alternate" hreflang="${hreflang}" href="${href}"/>`;

export const GET: APIRoute = async ({ site }) => {
  const url = (code: LocaleCode) => urlFor(code, site);
  const alternates = [...locales.map((locale) => link(locale.tag, url(locale.code))), link('x-default', url(defaultLocale))].join('');
  const pages = locales.map((locale) => `<url><loc>${url(locale.code)}</loc>${alternates}</url>`);

  const guides = [...(await pageGroups()).entries()].flatMap(([slug, versions]) => {
    const { links, xDefault } = alternatesOf(versions.keys(), (code) => absolute(pagePath(code, slug), site));
    const named = [...links.map((version) => link(localeByCode(version.code).tag, version.href)), link('x-default', xDefault)].join('');
    return links.map((version) => {
      const updated = versions.get(version.code)?.data.updated.toISOString().slice(0, 10);
      return `<url><loc>${version.href}</loc>${updated ? `<lastmod>${updated}</lastmod>` : ''}${named}</url>`;
    });
  });

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${[...pages, ...guides].join('\n')}
</urlset>
`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
