// Every crawler is welcome, and pointed to the sitemap once the site's address is known (astro.config `site`).
import type { APIRoute } from 'astro';
import { basePath } from '../copy/locales';

export const GET: APIRoute = ({ site }) => {
  const lines = ['User-agent: *', 'Allow: /'];
  if (site) lines.push('', `Sitemap: ${new URL(`${basePath}sitemap.xml`, site).href}`);
  return new Response(`${lines.join('\n')}\n`, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
