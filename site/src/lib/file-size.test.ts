import { describe, expect, it } from 'vitest';
import { fileSize } from './file-size';

// Each pair is what the app shows: Foundation's `.byteCount(style: .file)` in en_US and uk_UA on macOS 26.
describe('fileSize', () => {
  it('matches the app in English', () => {
    expect(fileSize(1, 'en')).toBe('1 byte');
    expect(fileSize(512, 'en')).toBe('512 bytes');
    expect(fileSize(860_000, 'en')).toBe('860 kB');
    expect(fileSize(2_114_560, 'en')).toBe('2.1 MB');
    expect(fileSize(48_213_504, 'en')).toBe('48.2 MB');
    expect(fileSize(61_734_912, 'en')).toBe('61.7 MB');
    expect(fileSize(48_000_000, 'en')).toBe('48 MB');
    expect(fileSize(1_234_567_890, 'en')).toBe('1.23 GB');
  });

  it('matches the app in Ukrainian', () => {
    expect(fileSize(1, 'uk')).toBe('1 байт');
    expect(fileSize(512, 'uk')).toBe('512 байтів');
    expect(fileSize(860_000, 'uk')).toBe('860 кБ');
    expect(fileSize(2_114_560, 'uk')).toBe('2,1 МБ');
    expect(fileSize(48_213_504, 'uk')).toBe('48,2 МБ');
    expect(fileSize(61_734_912, 'uk')).toBe('61,7 МБ');
    expect(fileSize(48_000_000, 'uk')).toBe('48 МБ');
    expect(fileSize(1_234_567_890, 'uk')).toBe('1,23 ГБ');
  });

  it('counts bytes with Ukrainian plural forms', () => {
    expect(fileSize(3, 'uk')).toBe('3 байти');
    expect(fileSize(12, 'uk')).toBe('12 байтів');
    expect(fileSize(21, 'uk')).toBe('21 байт');
  });
});
