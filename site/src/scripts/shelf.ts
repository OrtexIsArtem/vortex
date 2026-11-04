// The page's shelf: files put aside, newest first. Each arrival flashes the notch in the app's colors, blue for the
// first new file, green for the second, then white, and the closed notch shows a tray with their number. Looking at
// the shelf starts the count over. Real files dropped from the visitor's desktop show only their name and size; an
// image's preview is made in the browser, and nothing is uploaded.
import { flash, setIndicator, type FlashColor } from './notch';

export interface ShelfItem {
  id: number;
  name: string;
  /** In bytes; null for a folder. */
  size: number | null;
  addedAt: number;
  /** New since the visitor last looked at the shelf. */
  fresh: boolean;
  /** An object URL of an image's own picture, made in the browser. */
  preview?: string;
}

export interface Arrival {
  name: string;
  size: number | null;
  preview?: string;
}

type Listener = (items: ShelfItem[]) => void;

const listeners = new Set<Listener>();
let items: ShelfItem[] = [];
let nextId = 1;
/** New files since the last look, for the flash's color. */
let newCount = 0;

function emit(): void {
  setIndicator(
    'shelf',
    items.length ? { right: [{ kind: 'icon', name: 'tray' }, { kind: 'text', text: String(items.length) }], priority: 5 } : null,
  );
  for (const listener of listeners) listener(items);
}

export function onShelf(listener: Listener): () => void {
  listeners.add(listener);
  listener(items);
  return () => listeners.delete(listener);
}

/** Puts files on the shelf; the same name moves to the front instead of being added again. */
export function putOnShelf(arrivals: Arrival[]): void {
  if (!arrivals.length) return;
  for (const arrival of arrivals) {
    const existing = items.find((item) => item.name === arrival.name);
    if (existing) {
      if (existing.preview && existing.preview !== arrival.preview) URL.revokeObjectURL(existing.preview);
      items = items.filter((item) => item !== existing);
    }
    items.unshift({ id: nextId++, ...arrival, addedAt: Date.now(), fresh: true });
    newCount++;
  }
  const color: FlashColor = newCount === 1 ? 'glow-1' : newCount === 2 ? 'glow-2' : 'white';
  flash(color);
  emit();
}

export function takeOff(id: number): void {
  const item = items.find((candidate) => candidate.id === id);
  if (item?.preview) URL.revokeObjectURL(item.preview);
  items = items.filter((candidate) => candidate.id !== id);
  emit();
}

/** The visitor has seen the shelf: the dots go and the next arrival flashes blue again. */
export function lookedAtShelf(): void {
  newCount = 0;
  if (!items.some((item) => item.fresh)) return;
  for (const item of items) item.fresh = false;
  emit();
}

/** The extension, for a tile without a picture: ".aab". */
export function extension(name: string): string {
  const dot = name.lastIndexOf('.');
  return dot > 0 && dot < name.length - 1 ? name.slice(dot).toLowerCase() : '';
}
