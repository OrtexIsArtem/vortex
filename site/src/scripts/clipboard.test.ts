import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type * as Clipboard from './clipboard';

// The page as the history sees it: a document in English, the browser's async clipboard and the site's own files.
// What the clipboard is given is kept here instead.
let written: { type: string; data: string | Blob }[];

class FakeClipboardItem {
  constructor(readonly data: Record<string, Promise<Blob> | Blob>) {}
}

const picture = readFileSync(new URL('../../public/vortex-logo.png', import.meta.url));

/** The history as a page that has just loaded it. */
async function load(): Promise<typeof Clipboard> {
  vi.resetModules();
  return import('./clipboard');
}

function itemsOf(clipboard: typeof Clipboard): Clipboard.CopyItem[] {
  let items: Clipboard.CopyItem[] = [];
  clipboard.onClipboard((next) => (items = next))();
  return items;
}

beforeEach(() => {
  written = [];
  vi.stubGlobal('document', {
    documentElement: { dataset: { locale: 'en' }, lang: 'en' },
    addEventListener: () => {},
    getSelection: () => null,
  });
  vi.stubGlobal('navigator', {
    clipboard: {
      writeText: async (text: string) => void written.push({ type: 'text/plain', data: text }),
      write: async (items: FakeClipboardItem[]) => {
        for (const item of items) for (const [type, data] of Object.entries(item.data)) written.push({ type, data: await data });
      },
    },
  });
  vi.stubGlobal('ClipboardItem', FakeClipboardItem);
  vi.stubGlobal('fetch', vi.fn(async () => new Response(picture, { headers: { 'Content-Type': 'image/png' } })));
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('the page’s clipboard history', () => {
  it('copies what each sample shows: text as text, the image as its PNG', async () => {
    const clipboard = await load();
    for (const item of itemsOf(clipboard)) {
      written = [];
      expect(await clipboard.copyAgain(item.id), item.text).toBe(true);
      if (item.kind === 'image') {
        expect(fetch).toHaveBeenCalledWith(item.value);
        expect(written).toHaveLength(1);
        const [{ type, data }] = written;
        expect(type).toBe('image/png');
        expect(data).toBeInstanceOf(Blob);
        expect((data as Blob).type).toBe('image/png');
        expect(Buffer.from(await (data as Blob).arrayBuffer()).equals(picture)).toBe(true);
      } else {
        expect(written).toEqual([{ type: 'text/plain', data: item.value }]);
      }
    }
  });

  it('keeps its variety, with nothing a web page can’t put on the clipboard', async () => {
    const kinds = itemsOf(await load()).map((item) => item.kind);
    expect(new Set(kinds)).toEqual(new Set(['text', 'link', 'image', 'secret', 'code']));
  });

  it('shows the Vortex logo as its image, a small PNG of the site’s', async () => {
    const image = itemsOf(await load()).find((item) => item.kind === 'image');
    expect(image?.value).toBe('/vortex-logo.png');
    expect(picture.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe(true);
    expect(picture.length).toBeLessThan(40_000);
  });

  it('moves a copied image to the top, as any copy again does', async () => {
    const clipboard = await load();
    const image = itemsOf(clipboard).find((item) => item.kind === 'image');
    await clipboard.copyAgain(image!.id);
    expect(itemsOf(clipboard)[0]?.id).toBe(image!.id);
  });

  it('fails quietly where a browser can’t copy pictures, and leaves the image where it was', async () => {
    vi.stubGlobal('ClipboardItem', undefined);
    const clipboard = await load();
    const before = itemsOf(clipboard);
    const image = before.find((item) => item.kind === 'image');
    expect(await clipboard.copyAgain(image!.id)).toBe(false);
    expect(written).toEqual([]);
    expect(itemsOf(clipboard).map((item) => item.id)).toEqual(before.map((item) => item.id));
  });

  it('fails quietly when the browser refuses the copy', async () => {
    vi.stubGlobal('navigator', {
      clipboard: {
        writeText: () => Promise.reject(new DOMException('Denied', 'NotAllowedError')),
        write: () => Promise.reject(new DOMException('Denied', 'NotAllowedError')),
      },
    });
    const clipboard = await load();
    for (const item of itemsOf(clipboard)) expect(await clipboard.copyAgain(item.id)).toBe(false);
  });

  it('records the address of the picture, copied as text, as text', async () => {
    const clipboard = await load();
    const image = itemsOf(clipboard).find((item) => item.kind === 'image');
    clipboard.record(image!.value, 'This page');
    const [newest] = itemsOf(clipboard);
    expect(newest).toMatchObject({ kind: 'text', value: image!.value });
    expect(itemsOf(clipboard).filter((item) => item.kind === 'image')).toHaveLength(1);
  });
});
