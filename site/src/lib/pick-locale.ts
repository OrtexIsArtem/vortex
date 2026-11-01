// Which of the site's languages a visitor's browser asks for, in its order of preference. Self-contained, with no
// imports: the page's head runs its source as is, before anything paints (layouts/Base.astro).

/**
 * The first of `preferred` (as `navigator.languages`) the site has, as one of `codes`; `fallback` when none is.
 * Chinese in the simplified script goes to `zh`, in the traditional script to nothing (the site has no page for it),
 * and so does a bare "zh" after a traditional one, as in zh-TW, zh; any Portuguese goes to `pt-br`.
 */
export function pickLocale(preferred: readonly string[], codes: readonly string[], fallback: string): string {
  let traditionalChinese = false;
  for (const raw of preferred) {
    // A tag may carry a weight, as in an Accept-Language header ("de;q=0.9").
    const tag = (raw.split(';')[0] ?? '').trim().toLowerCase();
    const [language = '', ...rest] = tag.split('-');
    let code = language;
    if (language === 'zh') {
      const traditional = rest.some((part) => part === 'hant' || part === 'tw' || part === 'hk' || part === 'mo');
      if (traditional) traditionalChinese = true;
      // Traditional Chinese has no page here, and a bare "zh" after it means the same.
      if (traditional || (!rest.length && traditionalChinese)) continue;
    } else if (language === 'pt') {
      code = 'pt-br';
    }
    if (codes.includes(code)) return code;
  }
  return fallback;
}

/**
 * Whether `referrer` is a search engine's results page. A search engine already sent its visitor to the language it
 * picked for the search, so the root page keeps them there.
 */
export function fromSearch(referrer: string): boolean {
  let host: string;
  try {
    host = new URL(referrer).hostname.toLowerCase();
  } catch (error) {
    return false;
  }
  return /(^|\.)(google|bing|duckduckgo|yahoo|yandex|baidu|ecosia|qwant|naver|startpage|brave|kagi|sogou|seznam)\.[a-z.]+$/.test(host);
}
