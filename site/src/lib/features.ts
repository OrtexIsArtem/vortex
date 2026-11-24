// The landing's features in the page's order, in its own words: the chapters, then Features, where they are chosen.
// llms.txt describes them and the structured data names them (featureList), so neither drifts from the page.
import type { Copy } from '../copy/types';

/** The chapters as the landing shows them (components/Landing.astro), each with its anchor. */
export function chaptersOf(copy: Copy) {
  return [
    { id: 'timer', chapter: copy.timerChapter },
    { id: 'clipboard', chapter: copy.clipboardChapter },
    { id: 'shelf', chapter: copy.shelfChapter },
    { id: 'tasks', chapter: copy.tasksChapter },
    { id: 'keys', chapter: copy.keysChapter },
    { id: 'keyboard', chapter: copy.keyboardChapter },
    { id: 'screentext', chapter: copy.screenTextChapter },
    { id: 'home', chapter: copy.homeChapter },
  ] as const;
}

/** What the app does, a line per feature in the page's language: its name in the app and its chapter's claim, then
 *  the catalog where features are added and removed. */
export function featureList(copy: Copy): string[] {
  return [
    ...chaptersOf(copy).map(({ chapter }) => `${chapter.label}: ${chapter.title}`),
    `${copy.choose.label}: ${copy.choose.title}`,
  ];
}
