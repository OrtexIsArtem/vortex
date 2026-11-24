// Home's grid and where its widgets and the utilities button go, by the app's own rules (Packages/Features/Home:
// HomeLayout.swift, HomeFeature.swift and docs/behavior.md), on a display with the 186 pt notch.

export type WidgetSize = 'small' | 'medium' | 'wide' | 'large' | 'full';

/** The cells each size takes: Small 1×1, Medium 2×1, Wide 4×1, Large 2×2, Full 4×2. */
export const widgetSizes: Record<WidgetSize, { columns: number; rows: number }> = {
  small: { columns: 1, rows: 1 },
  medium: { columns: 2, rows: 1 },
  wide: { columns: 4, rows: 1 },
  large: { columns: 2, rows: 2 },
  full: { columns: 4, rows: 2 },
};

/** "2×1": columns by rows, as the editor's size chips say it. */
export function sizeLabel(size: WidgetSize): string {
  const { columns, rows } = widgetSizes[size];
  return `${columns}×${rows}`;
}

/** The grid under the notch row: 4×2 cells of 143×182 pt, 12 pt apart, 8 pt from the sides. */
export const homeGrid = { columns: 4, rows: 2, cell: { width: 143, height: 182 }, gap: 12, side: 8 } as const;

/** Home's column, the regular window's tab past the 56 pt sidebar, and the row next to the notch at its top. */
export const homeColumn = { width: 624, height: 440, row: 52 } as const;

/** The notch where it cuts into Home's column: 186 × 32 in the regular window's middle. */
export const homeNotch = { x: 191, y: 0, width: 186, height: 32 } as const;

export interface Cell {
  column: number;
  row: number;
}

export interface Placement extends Cell {
  widget: string;
  size: WidgetSize;
}

export interface Point {
  x: number;
  y: number;
}

/** Where everything is on Home: one widget in the notch row, the others on the grid, and the utilities button's place,
 *  its center from the middle of Home's column and from its top; null in its slot at the row's right end. */
export interface HomeLayout {
  notchRow: string | null;
  placed: Placement[];
  button: Point | null;
}

/** Where a widget goes: the notch row, or the grid in its sizes, the first preferred. */
export type WidgetPlace = 'notchRow' | readonly WidgetSize[];

/** A widget's card on the grid, from the grid's top left: 8 pt in from the column's side, under the notch row. */
export function frame(column: number, row: number, size: WidgetSize): { x: number; y: number; width: number; height: number } {
  const { cell, gap, side } = homeGrid;
  const { columns, rows } = widgetSizes[size];
  return {
    x: side + column * (cell.width + gap),
    y: row * (cell.height + gap),
    width: columns * cell.width + (columns - 1) * gap,
    height: rows * cell.height + (rows - 1) * gap,
  };
}

/** The grid's cells as bits, row by row: bit `row × columns + column`; null where the size leaves the grid. */
function mask(size: WidgetSize, column: number, row: number): number | null {
  const { columns, rows } = widgetSizes[size];
  if (column < 0 || row < 0 || column + columns > homeGrid.columns || row + rows > homeGrid.rows) return null;
  let bits = 0;
  for (let r = row; r < row + rows; r++) for (let c = column; c < column + columns; c++) bits |= 1 << (r * homeGrid.columns + c);
  return bits;
}

/** Whether a widget of `size` fits with its top left cell at `column`, `row`: on the grid and on no other widget's
 *  cells, `ignoring`'s left out. */
export function fits(placed: readonly Placement[], size: WidgetSize, column: number, row: number, ignoring?: string): boolean {
  const own = mask(size, column, row);
  if (own === null) return false;
  return !placed.some((other) => other.widget !== ignoring && (mask(other.size, other.column, other.row) ?? 0) & own);
}

/** The first of `sizes` that fits somewhere, at its first free place: left to right, then top to bottom. */
export function firstFit(placed: readonly Placement[], sizes: readonly WidgetSize[]): (Cell & { size: WidgetSize }) | null {
  for (const size of sizes)
    for (let row = 0; row < homeGrid.rows; row++)
      for (let column = 0; column < homeGrid.columns; column++) if (fits(placed, size, column, row)) return { size, column, row };
  return null;
}

/** The cell nearest a dragged widget's top left corner once it has moved by `dx`, `dy`: past half a cell it goes on to
 *  the next one. */
export function cellMovedBy(placement: Placement, dx: number, dy: number): Cell {
  const { cell, gap, side } = homeGrid;
  const box = frame(placement.column, placement.row, placement.size);
  return {
    column: Math.round((box.x + dx - side) / (cell.width + gap)),
    row: Math.round((box.y + dy) / (cell.height + gap)),
  };
}

/** What moving the others costs, compared in order: how many moved, how many of those aren't at their swap place, and
 *  how far they went, as the sum of squared distances in cells. */
type Cost = [moved: number, offSwap: number, distance: number];

const add = (a: Cost, b: Cost): Cost => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const less = (a: Cost, b: Cost) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

interface Spot {
  cell: Cell;
  bits: number;
  cost: Cost;
}

/** Every place on the grid that takes `placement`'s size, in the order tried: its own, its swap place, then the others
 *  nearest first, in reading order. */
function spots(placement: Placement, swap: Cell): Spot[] {
  const all: Spot[] = [];
  for (let row = 0; row < homeGrid.rows; row++) {
    for (let column = 0; column < homeGrid.columns; column++) {
      const bits = mask(placement.size, column, row);
      if (bits === null) continue;
      const own = column === placement.column && row === placement.row;
      const atSwap = column === swap.column && row === swap.row;
      const distance = (column - placement.column) ** 2 + (row - placement.row) ** 2;
      all.push({ cell: { column, row }, bits, cost: [own ? 0 : 1, own || atSwap ? 0 : 1, distance] });
    }
  }
  return all.sort((a, b) => less(a.cost, b.cost) || a.cell.row - b.cell.row || a.cell.column - b.cell.column);
}

/**
 * The layout once `widget`, dragged, lands with its top left cell at `column`, `row`, and the widgets in its way move
 * aside. They first take the place it left, keeping how they lay: each moves by the reverse of the drag. One that
 * doesn't fit there goes to the nearest free place. Widgets not in the way move only when that is the only way to make
 * room. Null when the widget isn't on the grid, is there already, or the others can't all fit around it.
 */
export function moving(layout: HomeLayout, widget: string, column: number, row: number): HomeLayout | null {
  const draggedIndex = layout.placed.findIndex((placement) => placement.widget === widget);
  const dragged = layout.placed[draggedIndex];
  if (!dragged || (column === dragged.column && row === dragged.row)) return null;
  const landing = mask(dragged.size, column, row);
  if (landing === null) return null;
  const others = layout.placed.map((_, index) => index).filter((index) => index !== draggedIndex);
  const options = others.map((index) => {
    const other = layout.placed[index]!;
    return spots(other, { column: other.column - (column - dragged.column), row: other.row - (row - dragged.row) });
  });
  // Every arrangement of the others around the dragged widget, by branch and bound: the cost only grows as widgets are
  // placed, so a branch that costs as much as the best so far can't beat it, and a tie keeps the first.
  let best: { cost: Cost; chosen: Spot[] } | null = null;
  const chosen: Spot[] = [];
  const place = (index: number, taken: number, cost: Cost) => {
    if (best && less(cost, best.cost) >= 0) return;
    if (index === options.length) {
      best = { cost, chosen: [...chosen] };
      return;
    }
    for (const spot of options[index]!) {
      if (taken & spot.bits) continue;
      chosen.push(spot);
      place(index + 1, taken | spot.bits, add(cost, spot.cost));
      chosen.pop();
    }
  };
  place(0, landing, [0, 0, 0]);
  const found = best as { cost: Cost; chosen: Spot[] } | null;
  if (!found) return null;
  const placed = layout.placed.map((placement) => ({ ...placement }));
  placed[draggedIndex] = { ...dragged, column, row };
  others.forEach((index, order) => {
    const spot = found.chosen[order]!;
    placed[index] = { ...placed[index]!, column: spot.cell.column, row: spot.cell.row };
  });
  return { ...layout, placed };
}

/** A move from the keyboard: the widget goes a cell that way, or as many as it takes to find one where it lands; null
 *  where none is. */
export function nudged(layout: HomeLayout, widget: string, dx: number, dy: number): HomeLayout | null {
  const placement = layout.placed.find((item) => item.widget === widget);
  if (!placement || (dx === 0 && dy === 0)) return null;
  for (let step = 1; step < Math.max(homeGrid.columns, homeGrid.rows); step++) {
    const column = placement.column + dx * step;
    const row = placement.row + dy * step;
    if (column < 0 || row < 0 || column >= homeGrid.columns || row >= homeGrid.rows) return null;
    const moved = moving(layout, widget, column, row);
    if (moved) return moved;
  }
  return null;
}

/** The cells no widget covers. */
export function freeCells(placed: readonly Placement[]): Cell[] {
  const cells: Cell[] = [];
  for (let row = 0; row < homeGrid.rows; row++)
    for (let column = 0; column < homeGrid.columns; column++) if (fits(placed, 'small', column, row)) cells.push({ column, row });
  return cells;
}

/** The layout with the widget at `size`, keeping its top left corner, only if it fits there; null otherwise. */
export function resized(layout: HomeLayout, widget: string, size: WidgetSize): HomeLayout | null {
  const placement = layout.placed.find((item) => item.widget === widget);
  if (!placement || placement.size === size || !fits(layout.placed, size, placement.column, placement.row, widget)) return null;
  return { ...layout, placed: layout.placed.map((item) => (item.widget === widget ? { ...item, size } : item)) };
}

/** The layout without the widget; the others stay where they are. */
export function removed(layout: HomeLayout, widget: string): HomeLayout {
  return {
    ...layout,
    notchRow: layout.notchRow === widget ? null : layout.notchRow,
    placed: layout.placed.filter((item) => item.widget !== widget),
  };
}

/** Where a widget off Home would go: the notch row while it is free, or its size in the first free place that takes
 *  it; null without room. */
export function placeFor(layout: HomeLayout, widget: string, place: WidgetPlace, size?: WidgetSize): HomeLayout | null {
  if (layout.notchRow === widget || layout.placed.some((item) => item.widget === widget)) return null;
  if (place === 'notchRow') return layout.notchRow === null ? { ...layout, notchRow: widget } : null;
  const fit = firstFit(layout.placed, [size ?? place[0]!]);
  return fit ? { ...layout, placed: [...layout.placed, { widget, ...fit }] } : null;
}

// The utilities button

/** How far its center keeps from the column's edges and from the notch: its 28 pt circle's radius and 8 pt. */
const buttonInset = 14 + 8;

/** Its slot at the notch row's right end: the circle 8 pt from the column's right edge, in the row's middle. */
export const buttonSlot: Point = { x: homeColumn.width - buttonInset, y: homeColumn.row / 2 };

/** Where its center shows, from the top left of Home's column: in its slot without a place; otherwise at its place, or
 *  where that doesn't fit, at the nearest point that does: inside the column and clear of the notch, beside or below it. */
export function buttonCenter(place: Point | null): Point {
  if (!place) return { ...buttonSlot };
  const center = {
    x: Math.min(Math.max(homeColumn.width / 2 + place.x, buttonInset), homeColumn.width - buttonInset),
    y: Math.min(Math.max(place.y, buttonInset), homeColumn.height - buttonInset),
  };
  const clear = {
    left: homeNotch.x - buttonInset,
    right: homeNotch.x + homeNotch.width + buttonInset,
    bottom: homeNotch.y + homeNotch.height + buttonInset,
  };
  // As a CGRect holds a point: its maximum edges are outside it.
  if (center.x >= clear.left && center.x < clear.right && center.y < clear.bottom) {
    const left = center.x - clear.left;
    const right = clear.right - center.x;
    const below = clear.bottom - center.y;
    if (left <= Math.min(right, below)) center.x = clear.left;
    else if (right <= below) center.x = clear.right;
    else center.y = clear.bottom;
  }
  return center;
}

/** Its place once a drag drops its center at `point`, from the top left of Home's column: where it then shows, in whole
 *  points, or null, its slot, within 20 pt of the slot's center. */
export function buttonPlace(point: Point): Point | null {
  const middle = homeColumn.width / 2;
  const center = buttonCenter({ x: point.x - middle, y: point.y });
  if (Math.hypot(center.x - buttonSlot.x, center.y - buttonSlot.y) <= 20) return null;
  return { x: Math.round(center.x - middle), y: Math.round(center.y) };
}

/** A move from the keyboard: the button goes `step` points that way, or as many steps as it takes to get anywhere,
 *  past the notch too; the same place where it can't go further. */
export function nudgedButton(place: Point | null, dx: number, dy: number, step = 24): Point | null {
  const from = buttonCenter(place);
  for (let count = 1; count <= Math.ceil(homeColumn.width / step); count++) {
    const next = buttonPlace({ x: from.x + dx * step * count, y: from.y + dy * step * count });
    const center = buttonCenter(next);
    const gained = (center.x - from.x) * dx + (center.y - from.y) * dy;
    if (gained >= 1) return next;
  }
  return place;
}
