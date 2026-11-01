// The guides' addresses and languages (src/content/pages/<language>/<slug>.md): which page is where, which languages
// it exists in, and which version a page in another language links to. Pure, so the routes, the head, the sitemap and
// the tests share it.
import { defaultLocale, isLocaleCode, localeCodes, pathFor, type LocaleCode } from '../copy/locales';

/** A page's address: lowercase words joined by dashes, the same in every language. */
const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** Addresses the site's root already answers to: a language's landing page, and the page for a missing address. */
const reservedSlugs: ReadonlySet<string> = new Set(['404', ...localeCodes]);

export interface PageKey {
  lang: LocaleCode;
  slug: string;
}

/** A page's language and slug, from its id in the collection: its path, as in `en/claude-code-secrets`. */
export function pageKey(id: string): PageKey {
  const [lang, slug, ...rest] = id.split('/');
  if (!isLocaleCode(lang) || slug === undefined || rest.length > 0) {
    throw new Error(`[pages] ${id}: a page lives at src/content/pages/<language>/<slug>.md, with a language the site has`);
  }
  if (!slugPattern.test(slug) || reservedSlugs.has(slug)) {
    throw new Error(`[pages] ${id}: "${slug}" can't be an address: use lowercase words joined by dashes, not a language code`);
  }
  return { lang, slug };
}

/** A page's path: English under the site's root, every other language under its code, as the landing pages are. */
export function pagePath(lang: LocaleCode, slug: string): string {
  return `${pathFor(lang)}${slug}/`;
}

/** An address as search engines and previews want it: absolute once the site's address is known, its path until then. */
export function absolute(path: string, site: URL | undefined): string {
  return site ? new URL(path, site).href : path;
}

/** One language's version of a page. */
export interface Alternate {
  code: LocaleCode;
  href: string;
}

/**
 * The languages a page exists in, in the site's order of languages, each with its address; and the address that
 * stands for every other language (hreflang x-default): the English one, which every page has.
 */
export function alternatesOf(
  langs: Iterable<LocaleCode>,
  href: (code: LocaleCode) => string,
): { links: Alternate[]; xDefault: string } {
  const present = new Set(langs);
  if (!present.has(defaultLocale)) throw new Error('[pages] a page exists in English first');
  const links = localeCodes.filter((code) => present.has(code)).map((code) => ({ code, href: href(code) }));
  return { links, xDefault: href(defaultLocale) };
}

/** Every page's versions by language, under its slug; a page without its English version stops the build. */
export function groupPages<T extends { id: string }>(entries: readonly T[]): Map<string, Map<LocaleCode, T>> {
  const groups = new Map<string, Map<LocaleCode, T>>();
  for (const entry of entries) {
    const { lang, slug } = pageKey(entry.id);
    const versions = groups.get(slug) ?? new Map<LocaleCode, T>();
    versions.set(lang, entry);
    groups.set(slug, versions);
  }
  for (const [slug, versions] of groups) {
    if (!versions.has(defaultLocale)) {
      throw new Error(`[pages] ${slug} has no English version: add src/content/pages/en/${slug}.md first`);
    }
  }
  return groups;
}

/** The version a page in `code` links to: its own language's when there is one, else the English one. */
export function versionFor<T>(versions: ReadonlyMap<LocaleCode, T>, code: LocaleCode): { lang: LocaleCode; entry: T } {
  const own = versions.get(code);
  if (own !== undefined) return { lang: code, entry: own };
  const english = versions.get(defaultLocale);
  if (english === undefined) throw new Error('[pages] a page exists in English first');
  return { lang: defaultLocale, entry: english };
}
