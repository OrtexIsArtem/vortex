// The drum's geometry and how scrolling turns it, as in the app (Packages/Features/Timer/Sources/Views/DrumRuler.swift).

/** Ticks further round than this, in radians, are too crowded to draw. */
export const edgeAngle = 1.48;

/** A ruler wrapped around a drum seen from the front: under the mark the ticks stand `spacing` apart. */
export class DrumGeometry {
  constructor(
    readonly width: number,
    readonly spacing: number,
  ) {}

  get radius(): number {
    return this.width / 2;
  }

  /** How far the drum turns per minute, in radians. */
  get anglePerMinute(): number {
    return this.radius > 0 ? this.spacing / this.radius : 0;
  }

  /** How many minutes show on each side of the mark. */
  get reach(): number {
    return this.anglePerMinute > 0 ? Math.ceil(edgeAngle / this.anglePerMinute) : 0;
  }

  /** Where `minute` shows while `value` is under the mark, and how squarely it faces the viewer; null round the back. */
  spot(minute: number, value: number): { x: number; facing: number } | null {
    const angle = (minute - value) * this.anglePerMinute;
    if (this.anglePerMinute <= 0 || Math.abs(angle) > edgeAngle) return null;
    return { x: this.radius + this.radius * Math.sin(angle), facing: Math.cos(angle) };
  }

  /** The minute shown at `x`, to the nearest whole one, while `value` is under the mark. */
  minute(atX: number, value: number): number {
    if (this.anglePerMinute <= 0) return Math.round(value);
    const sine = Math.min(Math.max((atX - this.radius) / this.radius, -0.99), 0.99);
    return Math.round(value + Math.asin(sine) / this.anglePerMinute);
  }
}

/**
 * Turns wheel events into whole minutes. A mouse wheel turns the drum a minute per notch; a trackpad, a minute per
 * `points`. What is left towards the next minute is dropped when a new swipe starts or the fingers turn back, so every
 * swipe starts afresh. A swipe or scroll that moves the page down or to the right adds time.
 */
export class ScrollSteps {
  private remainder = 0;
  private last = -Infinity;

  /** `time` in ms; a pause longer than `gestureGap` starts a new swipe. */
  minutes(deltaX: number, deltaY: number, precise: boolean, points: number, time: number, gestureGap = 180): number {
    const push = Math.abs(deltaX) > Math.abs(deltaY) ? deltaX : deltaY;
    if (!precise) {
      this.remainder = 0;
      return push > 0 ? 1 : push < 0 ? -1 : 0;
    }
    if (time - this.last > gestureGap || (push !== 0 && this.remainder !== 0 && push > 0 !== this.remainder > 0)) {
      this.remainder = 0;
    }
    this.last = time;
    this.remainder += push;
    // `|| 0` turns -0 into 0.
    const steps = Math.trunc(this.remainder / points) || 0;
    this.remainder -= steps * points;
    return steps;
  }
}
