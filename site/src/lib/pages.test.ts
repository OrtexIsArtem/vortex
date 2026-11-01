import { describe, expect, it } from 'vitest';
import { absolute, alternatesOf, groupPages, pageKey, pagePath, versionFor } from './pages';

describe('pageKey', () => {
  it('reads the language from the folder and the slug from the file name', () => {
    expect(pageKey('en/claude-code-secrets')).toEqual({ lang: 'en', slug: 'claude-code-secrets' });
    expect(pageKey('pt-br/keyboard-cleaning')).toEqual({ lang: 'pt-br', slug: 'keyboard-cleaning' });
  });

  it('refuses a folder that is not one of the languages', () => {
    expect(() => pageKey('ru/claude-code-secrets')).toThrow(/language/);
    expect(() => pageKey('claude-code-secrets')).toThrow(/language/);
    expect(() => pageKey('en/guides/claude-code-secrets')).toThrow(/language/);
  });

  it('refuses addresses the site already uses, or that are not lowercase words', () => {
    expect(() => pageKey('en/de')).toThrow(/address/);
    expect(() => pageKey('en/404')).toThrow(/address/);
    expect(() => pageKey('en/Claude_Code')).toThrow(/address/);
    expect(() => pageKey('en/-secrets')).toThrow(/address/);
  });
});

describe('pagePath', () => {
  it('puts English at the root and every other language under its code', () => {
    expect(pagePath('en', 'claude-code-secrets')).toBe('/claude-code-secrets/');
    expect(pagePath('de', 'claude-code-secrets')).toBe('/de/claude-code-secrets/');
  });
});

describe('absolute', () => {
  it('is absolute once the site has an address, a path before', () => {
    expect(absolute('/de/x/', new URL('https://vortex-notch.web.app'))).toBe('https://vortex-notch.web.app/de/x/');
    expect(absolute('/de/x/', undefined)).toBe('/de/x/');
  });
});

describe('alternatesOf', () => {
  const href = (code: string) => `https://example.com/${code}/x/`;

  it('lists only the languages the page has, in the site order, with English as x-default', () => {
    expect(alternatesOf(['ja', 'en', 'de'], href)).toEqual({
      links: [
        { code: 'en', href: 'https://example.com/en/x/' },
        { code: 'de', href: 'https://example.com/de/x/' },
        { code: 'ja', href: 'https://example.com/ja/x/' },
      ],
      xDefault: 'https://example.com/en/x/',
    });
  });

  it('gives an English-only page itself as its only language and as x-default', () => {
    expect(alternatesOf(['en'], href)).toEqual({ links: [{ code: 'en', href: 'https://example.com/en/x/' }], xDefault: 'https://example.com/en/x/' });
  });

  it('refuses a page without English', () => {
    expect(() => alternatesOf(['de'], href)).toThrow(/English/);
  });
});

describe('groupPages', () => {
  it('groups translations under their slug', () => {
    const groups = groupPages([{ id: 'en/a' }, { id: 'de/a' }, { id: 'en/b' }]);
    expect([...groups.keys()]).toEqual(['a', 'b']);
    expect([...(groups.get('a')?.keys() ?? [])]).toEqual(['en', 'de']);
  });

  it('stops at a translation whose English page is missing', () => {
    expect(() => groupPages([{ id: 'en/a' }, { id: 'de/b' }])).toThrow(/b has no English version/);
  });
});

describe('versionFor', () => {
  const versions = new Map([
    ['en', 'English page'],
    ['de', 'German page'],
  ] as const);

  it('takes the page in the visitor’s language when it exists', () => {
    expect(versionFor(versions, 'de')).toEqual({ lang: 'de', entry: 'German page' });
  });

  it('falls back to English otherwise', () => {
    expect(versionFor(versions, 'ja')).toEqual({ lang: 'en', entry: 'English page' });
  });
});
