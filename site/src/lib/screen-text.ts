// What Screen Text takes from a frame, as the app reads one (Packages/Features/ScreenText/docs/behavior.md): the lines
// under it, top to bottom, each without the spaces around it, and no blank ones. Boxes are in one space, the frozen
// screen's.

export interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface ScreenLine {
  box: Box;
  text: string;
}

/** A frame narrower or shorter than this is a click, which ends the capture quietly, as in the app. */
export const minFrame = 8;

/** How much of a line a frame has to cross, unless the line is shorter: a frame that only grazes it doesn't read it. */
const minCross = 12;

/** The rectangle between where a drag began and where the pointer is, whichever way it went. */
export function frameBetween(start: { x: number; y: number }, end: { x: number; y: number }): Box {
  return { x: Math.min(start.x, end.x), y: Math.min(start.y, end.y), w: Math.abs(end.x - start.x), h: Math.abs(end.y - start.y) };
}

/** The lines a frame reads: those whose middle it covers from top to bottom and that it crosses from side to side. */
export function framedLines(frame: Box, lines: readonly ScreenLine[]): string[] {
  return lines
    .filter(({ box }) => {
      const middle = box.y + box.h / 2;
      const across = Math.min(frame.x + frame.w, box.x + box.w) - Math.max(frame.x, box.x);
      return middle >= frame.y && middle <= frame.y + frame.h && across >= Math.min(minCross, box.w);
    })
    .sort((a, b) => a.box.y - b.box.y || a.box.x - b.box.x)
    .map(({ text }) => text.trim())
    .filter(Boolean);
}
