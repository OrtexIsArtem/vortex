import { describe, expect, it } from 'vitest';
import { DrumGeometry, ScrollSteps } from './drum-core';

describe('DrumGeometry', () => {
  const drum = new DrumGeometry(116, 6);

  it('puts the minute under the mark in the middle, facing the viewer', () => {
    const spot = drum.spot(5, 5);
    expect(spot?.x).toBeCloseTo(58);
    expect(spot?.facing).toBeCloseTo(1);
  });

  it('crowds the ticks towards the edges and hides those round the back', () => {
    const next = drum.spot(6, 5)!;
    const far = drum.spot(14, 5)!;
    const farther = drum.spot(15, 5)!;
    expect(next.x - 58).toBeGreaterThan(farther.x - far.x);
    expect(far.facing).toBeLessThan(next.facing);
    expect(drum.spot(5 + drum.reach + 2, 5)).toBeNull();
  });

  it('turns a click on a tick into its minute', () => {
    expect(drum.minute(58, 5)).toBe(5);
    expect(drum.minute(drum.spot(9, 5)!.x, 5)).toBe(9);
    expect(drum.minute(drum.spot(2, 5)!.x, 5)).toBe(2);
  });
});

describe('ScrollSteps', () => {
  it('turns a minute per mouse wheel notch', () => {
    const steps = new ScrollSteps();
    expect(steps.minutes(0, 100, false, 16, 0)).toBe(1);
    expect(steps.minutes(0, -4, false, 16, 10)).toBe(-1);
  });

  it('turns a minute per 16 points of a trackpad swipe and keeps the rest', () => {
    const steps = new ScrollSteps();
    expect(steps.minutes(0, 10, true, 16, 0)).toBe(0);
    expect(steps.minutes(0, 10, true, 16, 16)).toBe(1);
    expect(steps.minutes(0, 30, true, 16, 32)).toBe(2);
  });

  it('starts afresh when the fingers turn back or a new swipe begins', () => {
    const steps = new ScrollSteps();
    steps.minutes(0, 12, true, 16, 0);
    expect(steps.minutes(0, -6, true, 16, 16)).toBe(0);
    expect(steps.minutes(0, -12, true, 16, 32)).toBe(-1);
    steps.minutes(0, 12, true, 16, 48);
    expect(steps.minutes(0, 8, true, 16, 1000)).toBe(0);
  });

  it('follows the stronger axis', () => {
    const steps = new ScrollSteps();
    expect(steps.minutes(40, 3, true, 16, 0)).toBe(2);
  });
});
