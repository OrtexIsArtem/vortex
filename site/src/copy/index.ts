// The page's words while pages are built: every language's dictionary in this folder, by its file name. A language
// whose file isn't there reads as English. The browser loads only its own page's dictionary (scripts/copy.ts).
import { en } from './en';
import { defaultLocale, localeOf, type LocaleCode } from './locales';
import type { Copy } from './types';

const files = import.meta.glob<Record<string, Copy>>(['./*.ts', '!./index.ts', '!./locales.ts', '!./types.ts', '!./en.ts'], {
  eager: true,
});

const dictionaries = new Map<string, Copy>([[defaultLocale, en]]);
for (const [path, module] of Object.entries(files)) {
  const words = Object.values(module)[0];
  if (words) dictionaries.set(path.slice(2, -3), words);
}

export function copyOf(code: LocaleCode): Copy {
  return dictionaries.get(code) ?? en;
}

/** The words of the page at `url`. */
export function copyFor(url: URL): Copy {
  return copyOf(localeOf(url.pathname));
}
