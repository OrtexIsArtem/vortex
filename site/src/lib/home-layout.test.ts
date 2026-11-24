import { describe, expect, it } from 'vitest';
import {
  buttonCenter,
  buttonPlace,
  cellMovedBy,
  firstFit,
  fits,
  freeCells,
  moving,
  nudged,
  nudgedButton,
  placeFor,
  removed,
  resized,
  sizeLabel,
  type HomeLayout,
  type Placement,
} from './home-layout';

// The same cases as the app's HomeLayoutTests, so the page moves widgets as Vortex does.
const p = (widget: string, size: Placement['size'], column: number, row: number): Placement => ({ widget, size, column, row });
const grid = (...placed: Placement[]): HomeLayout => ({ notchRow: null, placed, button: null });

/** The owner's Home: Shelf medium at (0,0), Clipboard's history large at (2,0), Timer in the notch row. */
const ownersHome: HomeLayout = {
  notchRow: 'timer.timer',
  placed: [p('shelf.files', 'medium', 0, 0), p('clipboard.history', 'large', 2, 0)],
  button: null,
};

describe('the grid', () => {
  it('names sizes as the chips do', () => {
    expect(sizeLabel('medium')).toBe('2×1');
    expect(sizeLabel('large')).toBe('2×2');
  });

  it('takes a widget where it fits, left to right, then top to bottom', () => {
    const layout = grid(p('a', 'medium', 0, 0));
    expect(firstFit(layout.placed, ['small'])).toEqual({ size: 'small', column: 2, row: 0 });
    expect(firstFit(layout.placed, ['wide', 'medium'])).toEqual({ size: 'wide', column: 0, row: 1 });
    expect(firstFit(grid(p('f', 'full', 0, 0)).placed, ['medium', 'small'])).toBeNull();
  });

  it('keeps widgets on the grid and off each other', () => {
    const layout = grid(p('a', 'large', 0, 0), p('b', 'medium', 2, 0));
    expect(fits(layout.placed, 'wide', 2, 0)).toBe(false);
    expect(fits(layout.placed, 'small', 1, 1)).toBe(false);
    expect(fits(layout.placed, 'small', 1, 1, 'a')).toBe(true);
    expect(fits(layout.placed, 'medium', 2, 1)).toBe(true);
    expect(freeCells(layout.placed)).toEqual([
      { column: 2, row: 1 },
      { column: 3, row: 1 },
    ]);
  });

  it('lands a dragged widget on the cell nearest its corner', () => {
    const shelf = p('shelf.files', 'medium', 2, 0);
    expect(cellMovedBy(shelf, 0, 0)).toEqual({ column: 2, row: 0 });
    expect(cellMovedBy(shelf, 0, 194)).toEqual({ column: 2, row: 1 });
    expect(cellMovedBy(shelf, -150, 10)).toEqual({ column: 1, row: 0 });
    expect(cellMovedBy(shelf, 80, 100)).toEqual({ column: 3, row: 1 });
    expect(cellMovedBy(shelf, 70, 90)).toEqual({ column: 2, row: 0 });
  });
});

describe('moving a widget onto others', () => {
  it('swaps two widgets, keeping the notch row and the order', () => {
    const clipboardFirst = moving(ownersHome, 'clipboard.history', 0, 0);
    expect(clipboardFirst).toEqual({
      notchRow: 'timer.timer',
      placed: [p('shelf.files', 'medium', 2, 0), p('clipboard.history', 'large', 0, 0)],
      button: null,
    });
    expect(moving(ownersHome, 'shelf.files', 2, 0)).toEqual(clipboardFirst);
  });

  it('sends a widget without room at its swap place to the nearest free place', () => {
    expect(moving(ownersHome, 'shelf.files', 2, 1)?.placed).toEqual([
      p('shelf.files', 'medium', 2, 1),
      p('clipboard.history', 'large', 0, 0),
    ]);
  });

  it('keeps how the widgets in the way lay', () => {
    const layout = grid(p('a', 'small', 0, 0), p('b', 'small', 1, 0), p('m', 'medium', 2, 0));
    expect(moving(layout, 'm', 0, 0)?.placed).toEqual([p('a', 'small', 2, 0), p('b', 'small', 3, 0), p('m', 'medium', 0, 0)]);
  });

  it('prefers the swap place to a nearer free one', () => {
    expect(moving(grid(p('x', 'small', 0, 0), p('y', 'small', 3, 0)), 'y', 0, 0)?.placed).toEqual([
      p('x', 'small', 3, 0),
      p('y', 'small', 0, 0),
    ]);
  });

  it('goes by reading order between places as near', () => {
    expect(moving(grid(p('d', 'small', 0, 0), p('x', 'medium', 1, 0)), 'd', 1, 0)?.placed).toEqual([
      p('d', 'small', 1, 0),
      p('x', 'medium', 2, 0),
    ]);
  });

  it('moves widgets not in the way only to make room', () => {
    const layout = grid(p('l', 'large', 0, 0), p('m', 'medium', 2, 0), p('a', 'small', 2, 1), p('b', 'small', 3, 1));
    expect(moving(layout, 'm', 0, 0)?.placed).toEqual([
      p('l', 'large', 2, 0),
      p('m', 'medium', 0, 0),
      p('a', 'small', 0, 1),
      p('b', 'small', 1, 1),
    ]);
    const roomy = grid(p('w', 'medium', 2, 0), p('d', 'small', 2, 1), p('n', 'small', 3, 1));
    expect(moving(roomy, 'd', 2, 0)?.placed).toEqual([p('w', 'medium', 1, 1), p('d', 'small', 2, 0), p('n', 'small', 3, 1)]);
  });

  it('moves fewer widgets rather than more of them to their swap places', () => {
    const layout = grid(p('a', 'small', 1, 0), p('b', 'small', 2, 0), p('d', 'medium', 0, 1), p('n', 'medium', 2, 1));
    expect(moving(layout, 'd', 1, 1)?.placed).toEqual([
      p('a', 'small', 1, 0),
      p('b', 'small', 3, 1),
      p('d', 'medium', 1, 1),
      p('n', 'medium', 2, 0),
    ]);
  });

  it("moves nothing where it can't go", () => {
    expect(moving(ownersHome, 'clipboard.history', 1, 0)).toBeNull();
    expect(moving(ownersHome, 'shelf.files', 3, 0)).toBeNull();
    expect(moving(ownersHome, 'shelf.files', 0, -1)).toBeNull();
    expect(moving(ownersHome, 'shelf.files', 0, 0)).toBeNull();
    expect(moving(ownersHome, 'timer.timer', 0, 1)).toBeNull();
  });
});

describe('the editor', () => {
  const twoLarge: HomeLayout = {
    notchRow: 'timer.timer',
    placed: [p('clipboard.history', 'large', 0, 0), p('shelf.files', 'large', 2, 0)],
    button: null,
  };

  it('moves a widget from the keyboard as far as it takes to land', () => {
    // A cell right, (1,0), has no room for the shelf; two cells right, they swap.
    expect(nudged(twoLarge, 'clipboard.history', 1, 0)?.placed).toEqual([
      p('clipboard.history', 'large', 2, 0),
      p('shelf.files', 'large', 0, 0),
    ]);
    expect(nudged(twoLarge, 'clipboard.history', -1, 0)).toBeNull();
    expect(nudged(twoLarge, 'clipboard.history', 0, 1)).toBeNull();
  });

  it('changes a size in place, only where it fits', () => {
    expect(resized(twoLarge, 'shelf.files', 'medium')?.placed[1]).toEqual(p('shelf.files', 'medium', 2, 0));
    expect(resized(twoLarge, 'shelf.files', 'wide')).toBeNull();
    expect(resized(twoLarge, 'shelf.files', 'large')).toBeNull();
  });

  it('removes a widget and leaves the others; Add puts it back where there is room', () => {
    const without = removed(twoLarge, 'clipboard.history');
    expect(without.placed).toEqual([p('shelf.files', 'large', 2, 0)]);
    expect(placeFor(without, 'clipboard.history', ['large', 'medium'])?.placed[1]).toEqual(p('clipboard.history', 'large', 0, 0));
    expect(placeFor(twoLarge, 'other.widget', ['medium'])).toBeNull();
    const noTimer = removed(twoLarge, 'timer.timer');
    expect(noTimer.notchRow).toBeNull();
    expect(placeFor(noTimer, 'timer.timer', 'notchRow')?.notchRow).toBe('timer.timer');
  });
});

describe('the utilities button', () => {
  it('shows in its slot, or at its place inside the column', () => {
    expect(buttonCenter(null)).toEqual({ x: 602, y: 26 });
    expect(buttonCenter({ x: -100, y: 200 })).toEqual({ x: 212, y: 200 });
    expect(buttonCenter({ x: -400, y: 0 })).toEqual({ x: 22, y: 22 });
    expect(buttonCenter({ x: 400, y: 500 })).toEqual({ x: 602, y: 418 });
    expect(buttonPlace({ x: -30, y: 470 })).toEqual({ x: -290, y: 418 });
  });

  it('keeps clear of the notch, beside it or below it', () => {
    expect(buttonPlace({ x: 200, y: 20 })).toEqual({ x: 169 - 312, y: 22 });
    expect(buttonPlace({ x: 390, y: 30 })).toEqual({ x: 399 - 312, y: 30 });
    expect(buttonPlace({ x: 284, y: 10 })).toEqual({ x: 284 - 312, y: 54 });
  });

  it('goes back to its slot within 20 points of it', () => {
    expect(buttonPlace({ x: 602 - 12, y: 26 + 16 })).toBeNull();
    expect(buttonPlace({ x: 602 - 12, y: 26 + 17 })).toEqual({ x: 278, y: 43 });
    expect(buttonPlace({ x: 680, y: 30 })).toBeNull();
  });

  it('moves from the keyboard, past the notch too, and stays put at an edge', () => {
    expect(nudgedButton(null, -1, 0)).toEqual({ x: 578 - 312, y: 26 });
    expect(nudgedButton(null, 0, -1)).toBeNull();
    expect(nudgedButton(null, 1, 0)).toBeNull();
    // Beside the notch, the next step left goes under it.
    const beside = { x: 399 - 312, y: 26 };
    expect(nudgedButton(beside, -1, 0)).toEqual({ x: 351 - 312, y: 54 });
  });
});
