// Every language's page, each naming all the others, as the pages' own hreflang links do (layouts/Base.astro).
import type { APIRoute } from 'astro';
import { defaultLocale, locales, urlFor, type LocaleCode } from '../copy/locales';

export const GET: APIRoute = ({ site }) => {
  const url = (code: LocaleCode) => urlFor(code, site);
  const alternates = [
    ...locales.map((locale) => `<xhtml:link rel="alternate" hreflang="${locale.tag}" href="${url(locale.code)}"/>`),
    `<xhtml:link rel="alternate" hreflang="x-default" href="${url(defaultLocale)}"/>`,
  ].join('');
  const pages = locales.map((locale) => `<url><loc>${url(locale.code)}</loc>${alternates}</url>`).join('\n');
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${pages}
</urlset>
`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
