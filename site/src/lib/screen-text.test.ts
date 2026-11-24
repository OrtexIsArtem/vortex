import { describe, expect, it } from 'vitest';
import { frameBetween, framedLines, type ScreenLine } from './screen-text';

// A chat's screenshot of a build log, as the scene lays it out: three lines 20 px apart, the second indented.
const log: ScreenLine[] = [
  { box: { x: 40, y: 100, w: 330, h: 16 }, text: "error: cannot find 'WeatherService' in scope" },
  { box: { x: 40, y: 120, w: 330, h: 16 }, text: '  --> Sources/Forecast/ForecastView.swift:42' },
  { box: { x: 40, y: 140, w: 230, h: 16 }, text: '** BUILD FAILED ** (1 failure)' },
];

describe('framedLines', () => {
  it('reads every line in the frame, top to bottom, without the spaces around them', () => {
    expect(framedLines({ x: 30, y: 94, w: 350, h: 68 }, log)).toEqual([
      "error: cannot find 'WeatherService' in scope",
      '--> Sources/Forecast/ForecastView.swift:42',
      '** BUILD FAILED ** (1 failure)',
    ]);
  });

  it('keeps the order of the screen, not of the list', () => {
    expect(framedLines({ x: 30, y: 94, w: 350, h: 68 }, [...log].reverse())).toHaveLength(3);
    expect(framedLines({ x: 30, y: 94, w: 350, h: 68 }, [...log].reverse())[0]).toMatch(/^error/);
  });

  it("leaves out a line whose middle the frame doesn't cover", () => {
    // The frame ends above the last line's middle, at 148.
    expect(framedLines({ x: 30, y: 94, w: 350, h: 50 }, log)).toHaveLength(2);
  });

  it('leaves out a line the frame only grazes from the side', () => {
    // The third line ends at 270: a frame starting at 262 crosses it by 8 px.
    expect(framedLines({ x: 262, y: 94, w: 120, h: 68 }, log)).toHaveLength(2);
  });

  it('reads nothing where there is no text, and no blank lines', () => {
    expect(framedLines({ x: 400, y: 94, w: 60, h: 68 }, log)).toEqual([]);
    expect(framedLines({ x: 0, y: 0, w: 100, h: 100 }, [{ box: { x: 10, y: 10, w: 50, h: 16 }, text: '   ' }])).toEqual([]);
  });
});

describe('frameBetween', () => {
  it('is the same rectangle whichever way the drag went', () => {
    expect(frameBetween({ x: 10, y: 20 }, { x: 110, y: 70 })).toEqual({ x: 10, y: 20, w: 100, h: 50 });
    expect(frameBetween({ x: 110, y: 70 }, { x: 10, y: 20 })).toEqual({ x: 10, y: 20, w: 100, h: 50 });
  });
});
