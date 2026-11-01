// The vortex the page draws: curves that wind into the notch (the app's welcome, WelcomePage.swift's SpiralCurve) and
// streaks that run down spirals into it. Both are drawn around a point, the notch's middle, on a 2D canvas.

export interface Funnel {
  /** Where the curves wind to: the middle of the notch, in the canvas's own coordinates. */
  cx: number;
  cy: number;
  /** The size the curves spread over. */
  width: number;
  height: number;
}

/** One curve of the welcome's vortex, winding in to the notch; at progress 1 it has shrunk into it. */
export function drawCurve(
  context: CanvasRenderingContext2D,
  funnel: Funnel,
  index: number,
  count: number,
  progress: number,
  alpha = 1,
): void {
  const share = index / count;
  const jitter = (index * 0.381966) % 1;
  const outer = Math.max(funnel.width, funnel.height) * (0.55 + 0.45 * jitter);
  const squeeze = Math.pow(1 - progress, 1.35);
  const start = share * Math.PI * 2 + progress * Math.PI * 1.6;
  const steps = 40;
  context.beginPath();
  for (let step = 0; step <= steps; step++) {
    const t = step / steps;
    const angle = start + t * Math.PI * 1.25;
    const radius = outer * (1 - 0.82 * t) * squeeze;
    const x = funnel.cx + Math.cos(angle) * radius;
    // Flattened below the notch, so the curves pour into it from the sides and below.
    const y = funnel.cy + Math.abs(Math.sin(angle)) * radius * 0.62;
    if (step === 0) context.moveTo(x, y);
    else context.lineTo(x, y);
  }
  const golden = (index * 0.618034) % 1;
  context.strokeStyle = `rgba(255, 255, 255, ${((0.18 + 0.62 * golden) * (1 - progress * 0.9) * alpha).toFixed(3)})`;
  context.stroke();
}

export interface StreakOptions {
  count: number;
  /** How strongly they show, 0 to 1. */
  strength: number;
  /** Where along their spirals they are; grows with time. */
  phase: number;
  /** The widest a spiral starts, in px. */
  reach: number;
}

/** A streak's length along its spiral, and the pieces it is drawn in, fading towards its tail. */
const streakLength = 0.24;
const streakPieces = 10;

/** Streaks running down spirals into the notch, each fading in far out and slipping under the notch. */
export function drawStreaks(context: CanvasRenderingContext2D, funnel: Funnel, options: StreakOptions): void {
  context.lineCap = 'round';
  context.lineWidth = 1.25;
  for (let index = 0; index < options.count; index++) {
    const jitter = (index * 0.381966) % 1;
    const golden = (index * 0.618034) % 1;
    const outer = options.reach * (0.55 + 0.45 * jitter);
    const start = (index / options.count) * Math.PI * 2;
    const head = (options.phase * (0.8 + 0.4 * golden) + golden) % 1;
    const point = (t: number) => {
      const angle = start + t * Math.PI * 1.6;
      const radius = outer * Math.pow(1 - t, 1.25);
      return [funnel.cx + Math.cos(angle) * radius, funnel.cy + Math.abs(Math.sin(angle)) * radius * 0.62] as const;
    };
    const base = (0.18 + 0.62 * golden) * 0.95 * options.strength;
    for (let piece = 0; piece < streakPieces; piece++) {
      const t0 = head - (streakLength * piece) / streakPieces;
      const t1 = head - (streakLength * (piece + 1)) / streakPieces;
      if (t1 < 0) break;
      const along = Math.min(1, t1 / 0.15) * Math.min(1, (1 - t0) / 0.18);
      const alpha = base * (1 - piece / streakPieces) * along;
      if (alpha < 0.004) continue;
      const [x0, y0] = point(t0);
      const [x1, y1] = point(t1);
      context.strokeStyle = `rgba(255, 255, 255, ${alpha.toFixed(3)})`;
      context.beginPath();
      context.moveTo(x1, y1);
      context.lineTo(x0, y0);
      context.stroke();
    }
  }
}
