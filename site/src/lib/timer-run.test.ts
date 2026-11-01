import { describe, expect, it } from 'vitest';
import {
  clampMinutes,
  clockText,
  fractionLeft,
  isOver,
  pause,
  remaining,
  resume,
  secondsLeft,
  startRun,
  totalMinutes,
  untilNextSecond,
} from './timer-run';

describe('clockText', () => {
  it('reads as the app does', () => {
    expect(clockText(1500)).toBe('25:00');
    expect(clockText(522)).toBe('8:42');
    expect(clockText(5)).toBe('0:05');
    expect(clockText(0)).toBe('0:00');
    expect(clockText(3900)).toBe('1:05:00');
    expect(clockText(7200)).toBe('2:00:00');
  });
});

describe('a run', () => {
  const start = 1_000;

  it('shows its whole length until a full second has passed', () => {
    const run = startRun(25, start);
    expect(secondsLeft(run, start)).toBe(1500);
    expect(secondsLeft(run, start + 0.5)).toBe(1500);
    expect(secondsLeft(run, start + 1)).toBe(1499);
    expect(totalMinutes(run)).toBe(25);
  });

  it('keeps the minutes within 1 to 120', () => {
    expect(clampMinutes(0)).toBe(1);
    expect(clampMinutes(121)).toBe(120);
    expect(startRun(500, start).total).toBe(7200);
  });

  it('is over once no whole second is left', () => {
    const run = startRun(1, start);
    expect(isOver(run, start + 59.5)).toBe(false);
    expect(isOver(run, start + 60)).toBe(true);
    expect(isOver(run, start + 600)).toBe(true);
    expect(remaining(run, start + 600)).toBe(0);
  });

  it('never shows more than its total, even with the clock set back', () => {
    const run = startRun(5, start);
    expect(remaining(run, start - 100)).toBe(300);
    expect(fractionLeft(run, start - 100)).toBe(1);
  });

  it('keeps the time left while paused and goes on from there', () => {
    const run = startRun(5, start);
    const paused = pause(run, start + 100);
    expect(secondsLeft(paused, start + 10_000)).toBe(200);
    expect(isOver(paused, start + 10_000)).toBe(false);
    const resumed = resume(paused, start + 10_000);
    expect(secondsLeft(resumed, start + 10_050)).toBe(150);
  });

  it('wakes at the next whole second', () => {
    const run = startRun(5, start);
    expect(untilNextSecond(run, start + 0.25)).toBeCloseTo(0.75);
    expect(untilNextSecond(run, start)).toBe(1);
  });
});
