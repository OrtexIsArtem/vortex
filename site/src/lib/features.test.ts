import { describe, expect, it } from 'vitest';
import { de } from '../copy/de';
import { en } from '../copy/en';
import { es } from '../copy/es';
import { fr } from '../copy/fr';
import { ja } from '../copy/ja';
import { ptBr } from '../copy/pt-br';
import { uk } from '../copy/uk';
import { zh } from '../copy/zh';
import { chaptersOf, featureList } from './features';

const others = { uk, de, fr, es, ptBr, ja, zh };

describe('featureList', () => {
  it('names every feature the page shows, in its order: Screen Text, Home and the catalog among them', () => {
    expect(featureList(en)).toEqual([
      'Timer: A focus timer in your notch.',
      'Clipboard: Clipboard history, one hover away.',
      'Shelf: A shelf for files.',
      'Tasks: Turn anything on screen into a task.',
      'Keys: Keys Claude Code can use but never see.',
      'Keyboard cleaning: Lock the keyboard to clean it.',
      "Screen Text: Copy text you can't select.",
      'Home: Lay out Home your way.',
      'Features: Only what you need.',
    ]);
  });

  it('names the same features in every language, in its own words', () => {
    for (const [code, copy] of Object.entries(others)) {
      const list = featureList(copy);
      expect(list, code).toHaveLength(featureList(en).length);
      expect(new Set(list).size, code).toBe(list.length);
    }
    expect(featureList(uk)).toContain('Текст з екрана: Копіюйте текст, який не виділити.');
    expect(featureList(uk)).toContain('Функції: Лише те, що вам потрібно.');
  });
});

describe('chaptersOf', () => {
  it('gives each chapter its anchor on the page', () => {
    expect(chaptersOf(en).map(({ id }) => id)).toEqual(['timer', 'clipboard', 'shelf', 'tasks', 'keys', 'keyboard', 'screentext', 'home']);
  });
});
