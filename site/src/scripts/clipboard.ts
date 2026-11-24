// The page's clipboard history: a few sample copies, then whatever the visitor copies on the page. Like the app, it
// keeps the newest first with pinned ones on top, and Vortex's own copies are not recorded again. Every item copies
// what it shows, so the samples are only what a web page can put on the clipboard: text and a picture, never a file.
import { basePath } from '../copy/locales';
import { copy } from './copy';

export type CopyKind = 'text' | 'code' | 'link' | 'image' | 'secret';

export interface CopyItem {
  id: number;
  kind: CopyKind;
  /** What the card shows: the text, a link's title, or for an image the app's word for one. */
  text: string;
  /** A link's host, or nothing. */
  detail?: string;
  /** What a click copies: the text, or for an image the address of its picture, a PNG on this site. */
  value: string;
  app: string;
  copiedAt: number;
  pinned: boolean;
}

type Listener = (items: CopyItem[]) => void;

/** How many unpinned copies the history keeps, as the app does. */
const keep = 10;
const listeners = new Set<Listener>();
let nextId = 1;
const minutesAgo = (minutes: number) => Date.now() - minutes * 60_000;
const samples = copy.clipboardChapter.samples;

let items: CopyItem[] = [
  { id: nextId++, kind: 'text', text: samples.note, value: samples.note, app: samples.notes, copiedAt: minutesAgo(2), pinned: false },
  { id: nextId++, kind: 'link', text: 'OrtexIsArtem/vortex', detail: 'github.com', value: 'https://github.com/OrtexIsArtem/vortex', app: samples.safari, copiedAt: minutesAgo(5), pinned: false },
  // The Vortex logo, which a click copies as a picture (og/render.mjs draws it).
  { id: nextId++, kind: 'image', text: copy.clipboardChapter.image, value: `${basePath}vortex-logo.png`, app: samples.screenshot, copiedAt: minutesAgo(9), pinned: false },
  { id: nextId++, kind: 'secret', text: 'correct horse battery staple', value: 'correct horse battery staple', app: samples.passwords, copiedAt: minutesAgo(12), pinned: false },
  { id: nextId++, kind: 'code', text: 'brew install xcodegen', value: 'brew install xcodegen', app: samples.terminal, copiedAt: minutesAgo(64), pinned: false },
];

function sorted(list: CopyItem[]): CopyItem[] {
  return [...list].sort((a, b) => Number(b.pinned) - Number(a.pinned) || b.copiedAt - a.copiedAt);
}

function emit(): void {
  items = sorted(items);
  for (const listener of listeners) listener(items);
}

export function onClipboard(listener: Listener): () => void {
  listeners.add(listener);
  listener(items);
  return () => listeners.delete(listener);
}

/** Records a copy; copying something already there moves it to the top instead. */
export function record(text: string, app: string): void {
  const value = text.trim();
  if (!value) return;
  const existing = items.find((item) => item.kind !== 'image' && item.value === value);
  if (existing) existing.copiedAt = Date.now();
  else items.push({ id: nextId++, kind: 'text', text: value.slice(0, 400), value, app, copiedAt: Date.now(), pinned: false });
  // The oldest unpinned copy goes when there are too many.
  const unpinned = sorted(items).filter((item) => !item.pinned);
  for (const old of unpinned.slice(keep)) items = items.filter((item) => item.id !== old.id);
  emit();
}

export function togglePin(id: number): void {
  const item = items.find((candidate) => candidate.id === id);
  if (!item) return;
  item.pinned = !item.pinned;
  emit();
}

export function remove(id: number): void {
  items = items.filter((item) => item.id !== id);
  emit();
}

/** Copies an item again, as a click does: text as text, an image as its PNG. The page's own copies are not recorded
 *  again. False when the browser keeps its clipboard to itself, as Firefox before 127 does with pictures. */
export async function copyAgain(id: number): Promise<boolean> {
  const item = items.find((candidate) => candidate.id === id);
  if (!item) return false;
  try {
    if (item.kind === 'image') {
      if (typeof ClipboardItem === 'undefined') return false;
      // The write starts within the click, the only time Safari lets a page copy, and waits there for the picture.
      const picture = fetch(item.value).then(async (response) => {
        if (!response.ok) throw new Error(`The picture is missing: ${response.status}`);
        return new Blob([await response.arrayBuffer()], { type: 'image/png' });
      });
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': picture })]);
    } else {
      await navigator.clipboard.writeText(item.value);
    }
  } catch {
    return false;
  }
  item.copiedAt = Date.now();
  emit();
  return true;
}

/** How long ago, in the app's words: "now", "5 min", "1 h". */
export function age(copiedAt: number, now = Date.now()): string {
  return copy.demo.ago(Math.floor((now - copiedAt) / 60_000));
}

// What the visitor copies on this page joins the history.
document.addEventListener('copy', () => {
  const selection = document.getSelection()?.toString() ?? '';
  window.setTimeout(() => record(selection, copy.clipboardChapter.thisPage));
});
