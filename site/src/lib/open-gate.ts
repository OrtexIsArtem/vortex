// When the "Point at the notch" scene holds the window open, as a pure state machine the scene's script feeds with
// where the scroll is. Timers are passed in, so tests can drive them.

export interface GateOptions {
  /** Over the stretch the text stays pinned, 0 to 1: open from `openAt`, shut again from `closeAt`. */
  openAt: number;
  closeAt: number;
  /** The scroll has to stay inside this long, in ms, before the window opens, so a fast pass doesn't flash it. */
  settle: number;
  open(): void;
  close(): void;
  setTimer(run: () => void, ms: number): number;
  clearTimer(id: number): void;
}

export class OpenGate {
  private holding = false;
  /** The visitor closed the window the scene opened: it stays shut until they scroll out of the scene and back. */
  private dismissed = false;
  private timer: number | null = null;
  private at = -Infinity;

  constructor(private readonly options: GateOptions) {}

  get isHolding(): boolean {
    return this.holding;
  }

  private inside(at: number): boolean {
    return at >= this.options.openAt && at < this.options.closeAt;
  }

  /** Where the scroll is now, over the pinned stretch. */
  update(at: number): void {
    this.at = at;
    if (!this.inside(at)) {
      this.dismissed = false;
      // A cancelled wait must be forgotten too, or the scene would think one is still running and never open again.
      if (this.timer !== null) {
        this.options.clearTimer(this.timer);
        this.timer = null;
      }
      if (this.holding) {
        this.holding = false;
        this.options.close();
      }
      return;
    }
    if (this.holding || this.dismissed || this.timer !== null) return;
    this.timer = this.options.setTimer(() => {
      this.timer = null;
      if (!this.inside(this.at) || this.dismissed) return;
      this.holding = true;
      this.options.open();
    }, this.options.settle);
  }

  /** The window the scene held open was closed by the visitor. */
  closedByVisitor(): void {
    if (!this.holding) return;
    this.holding = false;
    this.dismissed = true;
  }
}
