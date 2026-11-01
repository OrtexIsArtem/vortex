// The timer's run, as the app keeps it (Packages/Features/Timer/Sources/TimerRun.swift). Times are in seconds.

export const minuteRange = { min: 1, max: 120 } as const;
export const defaultMinutes = 5;

export function clampMinutes(minutes: number): number {
  return Math.min(Math.max(Math.round(minutes), minuteRange.min), minuteRange.max);
}

export type Phase = { kind: 'running'; endsAt: number } | { kind: 'paused'; remaining: number };

export interface Run {
  phase: Phase;
  /** The minutes started, in seconds: the ring shows the time left out of it. */
  total: number;
}

/** A run of `minutes` that starts at `now`. */
export function startRun(minutes: number, now: number): Run {
  const total = clampMinutes(minutes) * 60;
  return { phase: { kind: 'running', endsAt: now + total }, total };
}

export function isPaused(run: Run): boolean {
  return run.phase.kind === 'paused';
}

/** Seconds left: never below zero, and never more than the total, which a clock set back would otherwise exceed. */
export function remaining(run: Run, now: number): number {
  const left = run.phase.kind === 'running' ? run.phase.endsAt - now : run.phase.remaining;
  return Math.min(Math.max(left, 0), run.total);
}

/** Whole seconds left, rounded up, so 25:00 shows until a full second has passed; a millisecond is forgiven. */
export function secondsLeft(run: Run, now: number): number {
  return Math.max(Math.ceil(remaining(run, now) - 0.001), 0);
}

/** Time is up once no whole second is left; a paused run never runs out. */
export function isOver(run: Run, now: number): boolean {
  return !isPaused(run) && secondsLeft(run, now) === 0;
}

/** Time left out of the total, 0…1. */
export function fractionLeft(run: Run, now: number): number {
  return run.total > 0 ? Math.min(Math.max(remaining(run, now) / run.total, 0), 1) : 0;
}

/** How long until the shown time changes: until the time left reaches its next whole second. */
export function untilNextSecond(run: Run, now: number): number {
  const left = remaining(run, now);
  const fraction = left - Math.floor(left);
  return fraction < 0.001 ? 1 : fraction;
}

/** The total in whole minutes, for "of 25 min". */
export function totalMinutes(run: Run): number {
  return Math.round(run.total / 60);
}

export function pause(run: Run, now: number): Run {
  return isPaused(run) ? run : { ...run, phase: { kind: 'paused', remaining: remaining(run, now) } };
}

export function resume(run: Run, now: number): Run {
  return run.phase.kind === 'paused' ? { ...run, phase: { kind: 'running', endsAt: now + run.phase.remaining } } : run;
}

/** "25:00", "8:42", "0:05"; an hour or more "1:05:00". */
export function clockText(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(whole / 3600);
  const minutes = Math.floor((whole % 3600) / 60);
  const rest = String(whole % 60).padStart(2, '0');
  return hours > 0 ? `${hours}:${String(minutes).padStart(2, '0')}:${rest}` : `${minutes}:${rest}`;
}
