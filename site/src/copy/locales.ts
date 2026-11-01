// The languages the site speaks: the code in its URL, the tag for `lang` and hreflang, the locale social previews use,
// and the name in the language itself. English is the default, at the root; every other language has a page under its code.

export const locales = [
  { code: 'en', tag: 'en', og: 'en_US', name: 'English' },
  { code: 'uk', tag: 'uk', og: 'uk_UA', name: 'Українська' },
  { code: 'de', tag: 'de', og: 'de_DE', name: 'Deutsch' },
  { code: 'fr', tag: 'fr', og: 'fr_FR', name: 'Français' },
  { code: 'es', tag: 'es', og: 'es_ES', name: 'Español' },
  { code: 'pt-br', tag: 'pt-BR', og: 'pt_BR', name: 'Português (Brasil)' },
  { code: 'ja', tag: 'ja', og: 'ja_JP', name: '日本語' },
  { code: 'zh', tag: 'zh-Hans', og: 'zh_CN', name: '简体中文' },
] as const;

export type Locale = (typeof locales)[number];
export type LocaleCode = Locale['code'];

export const defaultLocale: LocaleCode = 'en';
export const localeCodes: readonly LocaleCode[] = locales.map((locale) => locale.code);

export function isLocaleCode(value: string | undefined): value is LocaleCode {
  return localeCodes.includes(value as LocaleCode);
}

/** Where the site lives: the root, or a folder when it is hosted under one (astro.config `base`). */
export const basePath: string = import.meta.env.BASE_URL.replace(/\/?$/, '/');

/** A language's page: English at the site's root, the others under their code. */
export function pathFor(code: LocaleCode): string {
  return code === defaultLocale ? basePath : `${basePath}${code}/`;
}

/** A language's page as search engines and previews want it: absolute once the site's address is known (astro.config
 * `site`), its path until then. */
export function urlFor(code: LocaleCode, site: URL | undefined): string {
  return site ? new URL(pathFor(code), site).href : pathFor(code);
}

/** The language of a page, from its path. */
export function localeOf(pathname: string): LocaleCode {
  const inside = pathname.startsWith(basePath) ? pathname.slice(basePath.length) : pathname.replace(/^\//, '');
  const first = inside.split('/')[0];
  return isLocaleCode(first) ? first : defaultLocale;
}

export function localeByCode(code: LocaleCode): Locale {
  return locales.find((locale) => locale.code === code) ?? locales[0];
}

/**
 * The language of the app's own words on a page (the demo window, the ears, the demo panels): the app speaks English
 * and Ukrainian, so on the other pages they stay English and carry `lang="en"` for screen readers. Undefined where they
 * are in the page's language.
 */
export function appLangOf(code: LocaleCode): 'en' | undefined {
  return code === 'en' || code === 'uk' ? undefined : 'en';
}

/** Between a heading's two halves: a space, except in Japanese and Chinese, whose sentences end in 。 and take none. */
export function headingGap(pathname: string): string {
  const code = localeOf(pathname);
  return code === 'ja' || code === 'zh' ? '' : ' ';
}
