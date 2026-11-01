// The page's words in the browser, in the page's language (`data-locale` on <html>). Each language is a chunk of its
// own: a page fetches only its own dictionary, and the scripts that use it wait for it.
import { appLangOf, defaultLocale, isLocaleCode } from '../copy/locales';
import type { Copy } from '../copy/types';

const files = import.meta.glob<Record<string, Copy>>(['../copy/*.ts', '!../copy/index.ts', '!../copy/locales.ts', '!../copy/types.ts']);
const code = document.documentElement.dataset.locale ?? defaultLocale;
const load = files[`../copy/${code}.ts`] ?? files[`../copy/${defaultLocale}.ts`];
if (!load) throw new Error('The English copy is missing');

export const copy = Object.values(await load())[0] as Copy;

/** The language of the app's own words on this page, for `lang` on what scripts write: undefined when it is the page's. */
export const appLang = appLangOf(isLocaleCode(code) ? code : defaultLocale);
