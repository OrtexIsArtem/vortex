// The guides as the site reads them from their collection (content.config.ts): every page with its translations, and
// the links other pages make to them. Which version a link takes is lib/pages.ts's.
import { getCollection, type CollectionEntry } from 'astro:content';
import { defaultLocale, type LocaleCode } from '../copy/locales';
import { groupPages, pageKey, pagePath, versionFor } from './pages';

export type Page = CollectionEntry<'pages'>;
export type ChapterId = NonNullable<Page['data']['chapter']>;

/** Every guide, by slug, with its versions by language. */
export async function pageGroups(): Promise<Map<string, Map<LocaleCode, Page>>> {
  return groupPages(await getCollection('pages'));
}

/** The routes' pages: every version in English (`[slug].astro`), or every other (`[locale]/[slug].astro`). */
export async function pageRoutes(english: boolean): Promise<{ lang: LocaleCode; slug: string; entry: Page }[]> {
  const groups = await pageGroups();
  return [...groups.values()].flatMap((versions) =>
    [...versions.entries()]
      .filter(([lang]) => (lang === defaultLocale) === english)
      .map(([, entry]) => ({ ...pageKey(entry.id), entry })),
  );
}

export interface GuideLink {
  href: string;
  /** The page's short name, its H1 and its description. */
  label: string;
  heading: string;
  description: string;
  /** Its language when the page linking to it is in another: the guide exists only in English so far. */
  lang: LocaleCode | undefined;
  chapter: ChapterId | undefined;
}

/** The guides a page in `code` links to, each in that language when it has it, else in English; oldest first. */
export async function guidesFor(code: LocaleCode): Promise<GuideLink[]> {
  const groups = await pageGroups();
  return [...groups.entries()]
    .map(([slug, versions]) => ({ slug, ...versionFor(versions, code) }))
    .sort((a, b) => a.entry.data.published.getTime() - b.entry.data.published.getTime() || a.slug.localeCompare(b.slug))
    .map(({ slug, lang, entry }) => ({
      href: pagePath(lang, slug),
      label: entry.data.label,
      heading: entry.data.heading,
      description: entry.data.description,
      lang: lang === code ? undefined : lang,
      chapter: entry.data.chapter,
    }));
}

/** The guides each landing chapter ends with, for the landing in `code`. */
export async function chapterGuides(code: LocaleCode): Promise<Map<ChapterId, GuideLink[]>> {
  const chapters = new Map<ChapterId, GuideLink[]>();
  for (const guide of await guidesFor(code)) {
    if (guide.chapter) chapters.set(guide.chapter, [...(chapters.get(guide.chapter) ?? []), guide]);
  }
  return chapters;
}
