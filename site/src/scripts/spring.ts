/** A spring with SwiftUI's parameters, so the site moves the way the app does. */
export interface Spring {
  /** Seconds for one swing, as SwiftUI's `response`. */
  response: number;
  /** 1 settles without overshooting, as SwiftUI's `dampingFraction`. */
  damping: number;
}

export const springs = {
  /** WindowController.openAnimation */
  open: { response: 0.38, damping: 0.82 },
  /** WindowController.closeAnimation */
  close: { response: 0.26, damping: 1 },
  ears: { response: 0.3, damping: 0.9 },
} satisfies Record<string, Spring>;

type Values<K extends string> = Record<K, number>;

/** Several numbers moving together on one spring; a new target takes over from where they are, velocity and all. */
export class SpringGroup<K extends string> {
  private x: Values<K>;
  private v: Values<K>;
  private target: Values<K>;
  private spec: Spring = springs.open;
  private frame = 0;
  private last = 0;
  private settled: (() => void) | null = null;

  constructor(
    initial: Values<K>,
    private readonly onFrame: (values: Values<K>) => void,
  ) {
    this.x = { ...initial };
    this.target = { ...initial };
    this.v = Object.fromEntries(Object.keys(initial).map((key) => [key, 0])) as Values<K>;
    onFrame(this.x);
  }

  get values(): Values<K> {
    return { ...this.x };
  }

  /** Jumps to `values` with no motion. */
  set(values: Values<K>): void {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.x = { ...values };
    this.target = { ...values };
    for (const key in this.v) this.v[key] = 0;
    this.onFrame(this.x);
    this.resolve();
  }

  /** Springs to `values`; resolves once they settle there, or when another target takes over. */
  to(values: Values<K>, spec: Spring): Promise<void> {
    this.resolve();
    this.target = { ...values };
    this.spec = spec;
    if (!this.frame) {
      this.last = performance.now();
      this.frame = requestAnimationFrame(this.tick);
    }
    return new Promise((resolve) => {
      this.settled = resolve;
    });
  }

  private resolve(): void {
    const settled = this.settled;
    this.settled = null;
    settled?.();
  }

  private tick = (now: number): void => {
    const dt = Math.min(0.064, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    const stiffness = ((2 * Math.PI) / this.spec.response) ** 2;
    const friction = (4 * Math.PI * this.spec.damping) / this.spec.response;
    const steps = Math.max(1, Math.ceil(dt * 240));
    const h = dt / steps;
    let resting = true;
    for (const key in this.x) {
      let x = this.x[key];
      let v = this.v[key];
      const target = this.target[key];
      for (let step = 0; step < steps; step++) {
        v += (-stiffness * (x - target) - friction * v) * h;
        x += v * h;
      }
      if (Math.abs(x - target) < 0.02 && Math.abs(v) < 0.5) {
        x = target;
        v = 0;
      } else {
        resting = false;
      }
      this.x[key] = x;
      this.v[key] = v;
    }
    this.onFrame(this.x);
    if (resting) {
      this.frame = 0;
      this.resolve();
    } else {
      this.frame = requestAnimationFrame(this.tick);
    }
  };
}
