import { describe, expect, it } from 'vitest';
import { fromSearch, pickLocale } from './pick-locale';

const codes = ['en', 'uk', 'de', 'fr', 'es', 'pt-br', 'ja', 'zh'];
const pick = (...preferred: string[]) => pickLocale(preferred, codes, 'en');

describe('pickLocale', () => {
  it('takes the first language the site has', () => {
    expect(pick('de-DE', 'en-US')).toBe('de');
    expect(pick('uk-UA', 'ru-RU', 'en')).toBe('uk');
  });

  it('keeps English when the browser puts it first', () => {
    expect(pick('en-GB', 'de-DE')).toBe('en');
  });

  it('skips languages the site lacks', () => {
    expect(pick('ru-RU', 'pl-PL', 'fr-FR')).toBe('fr');
    expect(pick('ko-KR')).toBe('en');
  });

  it('sends any Portuguese to the Brazilian page', () => {
    expect(pick('pt-BR')).toBe('pt-br');
    expect(pick('pt-PT')).toBe('pt-br');
    expect(pick('pt')).toBe('pt-br');
  });

  it('sends simplified Chinese to zh and passes over traditional', () => {
    expect(pick('zh-CN')).toBe('zh');
    expect(pick('zh-Hans-CN')).toBe('zh');
    expect(pick('zh')).toBe('zh');
    expect(pick('zh-TW', 'ja-JP')).toBe('ja');
    expect(pick('zh-Hant-HK')).toBe('en');
    expect(pick('zh-TW', 'zh', 'ja')).toBe('ja');
    expect(pick('zh-HK', 'zh-Hans')).toBe('zh');
  });

  it('reads tags that carry a weight', () => {
    expect(pick('de-DE', 'de;q=0.9', 'en;q=0.8')).toBe('de');
    expect(pick('ko;q=0.9', 'fr;q=0.8')).toBe('fr');
  });

  it('falls back with no languages at all', () => {
    expect(pick()).toBe('en');
  });
});

describe('fromSearch', () => {
  it('knows search engines, in any country', () => {
    expect(fromSearch('https://www.google.com/')).toBe(true);
    expect(fromSearch('https://www.google.com.ua/')).toBe(true);
    expect(fromSearch('https://www.bing.com/search?q=notch+app')).toBe(true);
    expect(fromSearch('https://duckduckgo.com/')).toBe(true);
    expect(fromSearch('https://search.brave.com/')).toBe(true);
    expect(fromSearch('https://yandex.ru/')).toBe(true);
    expect(fromSearch('android-app://com.google.android.googlequicksearchbox/')).toBe(true);
  });

  it('leaves other sites alone', () => {
    expect(fromSearch('https://github.com/OrtexIsArtem/vortex')).toBe(false);
    expect(fromSearch('https://t.co/abc')).toBe(false);
    expect(fromSearch('https://news.ycombinator.com/')).toBe(false);
    expect(fromSearch('https://googleusercontent.com/')).toBe(false);
    expect(fromSearch('https://mygoogle.example.com/')).toBe(false);
  });

  it('reads no referrer or a broken one as no search', () => {
    expect(fromSearch('')).toBe(false);
    expect(fromSearch('not a url')).toBe(false);
  });
});
