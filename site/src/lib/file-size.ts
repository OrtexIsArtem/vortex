// A file's size as the app's shelf shows it (Foundation's `.byteCount(style: .file)`): decimal units, whole bytes and
// kilobytes, megabytes to one decimal and gigabytes to two, trailing zeros dropped, in the app's language.

/** The languages the app speaks. */
export type AppLanguage = 'en' | 'uk';

const units: Record<AppLanguage, readonly string[]> = {
  en: ['kB', 'MB', 'GB'],
  uk: ['кБ', 'МБ', 'ГБ'],
};

/** "1 byte", "512 bytes"; «1 байт», «3 байти», «512 байтів». */
function bytes(count: number, language: AppLanguage): string {
  if (language === 'en') return `${count} ${count === 1 ? 'byte' : 'bytes'}`;
  const tens = count % 100;
  const ones = count % 10;
  const word = ones === 1 && tens !== 11 ? 'байт' : ones >= 2 && ones <= 4 && (tens < 12 || tens > 14) ? 'байти' : 'байтів';
  return `${count} ${word}`;
}

/** `value` as it shows with `digits` decimals. */
const rounded = (value: number, digits: number) => Math.round(value * 10 ** digits) / 10 ** digits;

/** "48.2 MB" or «48,2 МБ», "860 kB", "1.23 GB". */
export function fileSize(count: number, language: AppLanguage): string {
  if (count === 0) return language === 'en' ? 'Zero kB' : '0 кБ';
  if (count < 1000) return bytes(count, language);
  let value = count / 1000;
  let unit = 0;
  // By the value as shown, so 999,600 bytes read 1 MB, not 1,000 kB.
  while (rounded(value, unit) >= 1000 && unit < units[language].length - 1) {
    value /= 1000;
    unit++;
  }
  const number = value.toLocaleString(language, { maximumFractionDigits: unit });
  return `${number} ${units[language][unit]}`;
}
