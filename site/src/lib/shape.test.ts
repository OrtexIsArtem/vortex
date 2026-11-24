import { describe, expect, it } from 'vitest';
import { windowScale } from './shape';

describe('windowScale', () => {
  it('keeps the window whole where it fits', () => {
    expect(windowScale(1280, 800)).toBe(1);
    expect(windowScale(1280, 800, 56)).toBe(1);
  });

  it('fits a narrow screen, 16 px clear of each side', () => {
    expect(windowScale(375, 812)).toBeCloseTo(343 / 680);
  });

  it('fits the room the window grows at its right between the notch and the screen side', () => {
    // Hanging from the middle, the window reaches 340 to the left and 340 + 56 to the right.
    expect(windowScale(375, 812, 56)).toBeCloseTo(171.5 / 396);
    expect(windowScale(800, 900, 56)).toBeCloseTo(384 / 396);
    expect(windowScale(375, 812, 56)).toBeLessThan(windowScale(375, 812));
  });

  it('leaves room for the text under it on a short screen, but no less than 0.55', () => {
    expect(windowScale(1440, 600)).toBeCloseTo(260 / 440);
    expect(windowScale(1440, 400)).toBe(0.55);
    expect(windowScale(1440, 400, 56)).toBe(0.55);
  });
});
