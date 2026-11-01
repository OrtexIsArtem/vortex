// The timer's drum, drawn and turned as in the app (Packages/Features/Timer/Sources/Views/DrumRuler.swift): a ruler
// wrapped around a drum under a fixed mark, a tick per minute and a longer one every five; towards the edges the
// ticks crowd, shrink and fade. Scroll it, drag it, click a tick or use the arrow keys; while a run goes it shows the
// time left and takes no input.
import { DrumGeometry, ScrollSteps } from '../lib/drum-core';
import { clampMinutes, defaultMinutes, minuteRange } from '../lib/timer-run';

export interface DrumStyle {
  /** Between ticks under the mark; a drag turns the drum a minute per this many px, so it follows the pointer. */
  spacing: number;
  /** A trackpad turns it a minute per this many px. */
  scrollPoints: number;
  height: number;
  minorTick: number;
  majorTick: number;
  /** Where the ticks stand under the mark; round the drum they shrink towards `middle`. */
  baseline: number;
  middle: number;
  markTop: number;
  markHeight: number;
  showsNumbers: boolean;
}

export const drumStyles = {
  home: { spacing: 6, scrollPoints: 16, height: 34, minorTick: 7, majorTick: 12, baseline: 25, middle: 17, markTop: 4, markHeight: 23, showsNumbers: false },
  tab: { spacing: 9, scrollPoints: 23, height: 56, minorTick: 9, majorTick: 16, baseline: 32, middle: 22, markTop: 4, markHeight: 32, showsNumbers: true },
} satisfies Record<string, DrumStyle>;

const primary = '245, 245, 247';
const secondary = '#8E8E93';
const tertiary = '#7C7C82';

/** Draws the drum with `value` under the mark; `last` is the last minute with a tick. */
export function drawDrum(canvas: HTMLCanvasElement, value: number, last: number, style: DrumStyle): void {
  const context = canvas.getContext('2d');
  if (!context) return;
  const ratio = Math.min(2, window.devicePixelRatio || 1);
  const width = canvas.clientWidth;
  const height = style.height;
  if (!width) return;
  if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
  }
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, width, height);

  // A faint sheen where the drum faces the viewer.
  const sheen = context.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, width / 2);
  sheen.addColorStop(0, `rgba(${primary}, 0.06)`);
  sheen.addColorStop(1, `rgba(${primary}, 0)`);
  context.save();
  context.translate(0, height / 2);
  context.scale(1, height / width);
  context.translate(0, -height / 2);
  context.fillStyle = sheen;
  context.fillRect(0, (height - width) / 2, width, width);
  context.restore();

  const drum = new DrumGeometry(width, style.spacing);
  const under = Math.floor(value);
  const first = Math.max(0, under - drum.reach);
  const end = Math.max(first, Math.min(last, under + drum.reach));
  context.font = '10px ui-monospace, "SF Mono", Menlo, monospace';
  context.textAlign = 'center';
  context.textBaseline = 'top';
  for (let minute = first; minute <= end; minute++) {
    const spot = drum.spot(minute, value);
    if (!spot) continue;
    const nearness = 0.6 + 0.4 * spot.facing;
    const isMajor = minute % 5 === 0;
    const isLit = minute <= value + 0.0001;
    const tick = (isMajor ? style.majorTick : style.minorTick) * nearness;
    const bottom = style.middle + (style.baseline - style.middle) * nearness;
    const tickWidth = 0.8 + 0.7 * spot.facing;
    context.globalAlpha = 0.15 + 0.85 * spot.facing * spot.facing;
    context.fillStyle = isMajor
      ? isLit
        ? `rgb(${primary})`
        : `rgba(${primary}, 0.32)`
      : isLit
        ? secondary
        : `rgba(${primary}, 0.18)`;
    context.beginPath();
    context.roundRect(spot.x - tickWidth / 2, bottom - tick, tickWidth, tick, tickWidth / 2);
    context.fill();
    if (style.showsNumbers && isMajor && spot.facing > 0.35) {
      context.fillStyle = isLit ? secondary : tertiary;
      context.fillText(String(minute), spot.x, bottom + 5);
    }
  }
  context.globalAlpha = 1;

  // The ticks fade out towards both ends.
  const fade = context.createLinearGradient(0, 0, width, 0);
  fade.addColorStop(0, 'rgba(0, 0, 0, 0)');
  fade.addColorStop(0.16, 'rgba(0, 0, 0, 1)');
  fade.addColorStop(0.84, 'rgba(0, 0, 0, 1)');
  fade.addColorStop(1, 'rgba(0, 0, 0, 0)');
  context.globalCompositeOperation = 'destination-in';
  context.fillStyle = fade;
  context.fillRect(0, 0, width, height);
  context.globalCompositeOperation = 'source-over';

  // The fixed mark.
  context.fillStyle = `rgb(${primary})`;
  context.beginPath();
  context.roundRect(width / 2 - 1, style.markTop, 2, style.markHeight, 1);
  context.fill();
}

/** How long the page counts as scrolling after its last scroll: a wheel that starts then belongs to the page. */
const pageScrollGrace = 250;
let pageScrolledAt = -Infinity;
window.addEventListener('scroll', () => (pageScrolledAt = performance.now()), { passive: true });

interface DrumOptions {
  label: string;
  /** The minutes' unit, read out after the value ("25 min"). */
  unit: string;
  onChange?: (minutes: number) => void;
  /** A drag ended, maybe outside the window. */
  onRelease?: () => void;
}

/** A drum on a canvas that the visitor turns. */
export class DrumControl {
  minutes = defaultMinutes;
  private shown = defaultMinutes;
  private velocity = 0;
  private run: { value: number; last: number } | null = null;
  private frame = 0;
  private last = 0;
  private readonly steps = new ScrollSteps();
  private drag: { x: number; minutes: number; moved: boolean } | null = null;
  /** Whether the current wheel gesture turns the drum, or scrolls the page past it. */
  private wheelOwned = false;
  private wheelAt = -Infinity;
  private readonly reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly style: DrumStyle,
    private readonly options: DrumOptions,
  ) {
    canvas.tabIndex = 0;
    canvas.setAttribute('role', 'slider');
    canvas.setAttribute('aria-label', options.label);
    canvas.setAttribute('aria-valuemin', String(minuteRange.min));
    canvas.setAttribute('aria-valuemax', String(minuteRange.max));
    canvas.addEventListener('wheel', this.onWheel, { passive: false });
    canvas.addEventListener('pointerdown', this.onPointerDown);
    canvas.addEventListener('pointermove', this.onPointerMove);
    canvas.addEventListener('pointerup', this.onPointerUp);
    canvas.addEventListener('pointercancel', this.onPointerUp);
    canvas.addEventListener('keydown', this.onKey);
    new ResizeObserver(() => this.draw()).observe(canvas);
    this.updateAria();
    this.draw();
  }

  /** Turns the drum to `minutes`, within 1 to 120. */
  setMinutes(value: number, animated = true): void {
    const minutes = clampMinutes(value);
    const changed = minutes !== this.minutes;
    this.minutes = minutes;
    if (changed) {
      this.updateAria();
      this.options.onChange?.(minutes);
    }
    if (animated && !this.reduceMotion.matches) {
      if (!this.frame) {
        this.last = performance.now();
        this.frame = requestAnimationFrame(this.tick);
      }
    } else {
      cancelAnimationFrame(this.frame);
      this.frame = 0;
      this.shown = minutes;
      this.velocity = 0;
      this.draw();
    }
  }

  /** Shows a run's time left, in minutes, turning towards zero; null gives the drum back to the visitor. */
  showRun(value: number | null, last: number = minuteRange.max): void {
    this.run = value === null ? null : { value, last };
    this.canvas.classList.toggle('is-running', this.run !== null);
    this.canvas.setAttribute('aria-disabled', String(this.run !== null));
    this.drag = null;
    this.draw();
  }

  redraw(): void {
    this.draw();
  }

  private draw(): void {
    drawDrum(this.canvas, this.run ? this.run.value : this.shown, this.run ? this.run.last : minuteRange.max, this.style);
  }

  private updateAria(): void {
    this.canvas.setAttribute('aria-valuenow', String(this.minutes));
    this.canvas.setAttribute('aria-valuetext', `${this.minutes} ${this.options.unit}`);
  }

  /** The drum turns to a new minute on a quick spring, as SwiftUI's snappy turn of 0.2 s. */
  private tick = (now: number): void => {
    const dt = Math.min(0.05, (now - this.last) / 1000);
    this.last = now;
    const stiffness = ((2 * Math.PI) / 0.2) ** 2;
    const friction = (4 * Math.PI * 0.9) / 0.2;
    const steps = Math.max(1, Math.ceil(dt * 240));
    for (let step = 0; step < steps; step++) {
      this.velocity += (-stiffness * (this.shown - this.minutes) - friction * this.velocity) * (dt / steps);
      this.shown += this.velocity * (dt / steps);
    }
    if (Math.abs(this.shown - this.minutes) < 0.002 && Math.abs(this.velocity) < 0.05) {
      this.shown = this.minutes;
      this.velocity = 0;
      this.frame = 0;
    } else {
      this.frame = requestAnimationFrame(this.tick);
    }
    this.draw();
  };

  private onWheel = (event: WheelEvent): void => {
    if (this.run) return;
    const now = performance.now();
    // A new gesture belongs to the drum unless the page was scrolling a moment ago; a sideways swipe always does.
    if (now - this.wheelAt > 180) this.wheelOwned = now - pageScrolledAt > pageScrollGrace;
    this.wheelAt = now;
    if (!this.wheelOwned && Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
    event.preventDefault();
    const legacy = (event as WheelEvent & { wheelDeltaY?: number }).wheelDeltaY;
    const mouseWheel = event.deltaMode !== 0 || (legacy !== undefined && legacy !== 0 && legacy % 120 === 0 && Math.abs(event.deltaY) >= 30);
    const minutes = this.steps.minutes(event.deltaX, event.deltaY, !mouseWheel, this.style.scrollPoints * 1.4, now);
    if (minutes !== 0) this.setMinutes(this.minutes + minutes);
  };

  private onPointerDown = (event: PointerEvent): void => {
    if (this.run || event.button !== 0) return;
    this.canvas.setPointerCapture(event.pointerId);
    this.drag = { x: event.clientX, minutes: this.minutes, moved: false };
  };

  private onPointerMove = (event: PointerEvent): void => {
    const drag = this.drag;
    if (!drag) return;
    const scale = this.canvas.getBoundingClientRect().width / this.canvas.clientWidth || 1;
    const dx = (drag.x - event.clientX) / scale;
    if (!drag.moved && Math.abs(dx) > 2) drag.moved = true;
    // The drum follows the pointer: dragging to the left brings later minutes under the mark.
    if (drag.moved) this.setMinutes(drag.minutes + Math.round(dx / this.style.spacing));
  };

  private onPointerUp = (event: PointerEvent): void => {
    const drag = this.drag;
    this.drag = null;
    if (this.canvas.hasPointerCapture(event.pointerId)) this.canvas.releasePointerCapture(event.pointerId);
    if (!drag || event.type === 'pointercancel') return;
    if (!drag.moved) {
      // A click turns the tick under the pointer to the mark.
      const box = this.canvas.getBoundingClientRect();
      const x = ((event.clientX - box.left) / box.width) * this.canvas.clientWidth;
      const geometry = new DrumGeometry(this.canvas.clientWidth, this.style.spacing);
      this.setMinutes(geometry.minute(x, drag.minutes));
    }
    this.options.onRelease?.();
  };

  private onKey = (event: KeyboardEvent): void => {
    if (this.run) return;
    const steps: Record<string, number> = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1, PageUp: 5, PageDown: -5 };
    if (event.key in steps) this.setMinutes(this.minutes + (steps[event.key] ?? 0));
    else if (event.key === 'Home') this.setMinutes(minuteRange.min);
    else if (event.key === 'End') this.setMinutes(minuteRange.max);
    else return;
    event.preventDefault();
  };
}
