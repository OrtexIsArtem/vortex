// Drags drawn things across the page with the pointer: a copy follows the pointer, targets light up under it, a drop
// that misses flies back. A tap sends the thing to its tap target by itself, which is how touch screens use it; there a
// source should allow `touch-action: pan-y`, so a vertical swipe that starts on it still scrolls the page.

export interface DropTarget {
  contains(x: number, y: number): boolean;
  enter?(): void;
  leave?(): void;
  drop(): void;
  /** Where something tapped, or dropped, flies to, in the viewport. */
  point(): { x: number; y: number };
}

export interface DragOptions {
  targets: DropTarget[];
  tapTarget?: DropTarget;
  onStart?(): void;
  onEnd?(): void;
}

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');

function makeGhost(source: HTMLElement, box: DOMRect): HTMLElement {
  const ghost = source.cloneNode(true) as HTMLElement;
  ghost.classList.add('drag-ghost');
  // A copy must not take the ids the source's labels point to.
  ghost.removeAttribute('id');
  ghost.querySelectorAll('[id]').forEach((element) => element.removeAttribute('id'));
  ghost.setAttribute('aria-hidden', 'true');
  Object.assign(ghost.style, {
    position: 'fixed',
    left: `${box.left}px`,
    top: `${box.top}px`,
    width: `${box.width}px`,
    height: `${box.height}px`,
    margin: '0',
    zIndex: '70',
    pointerEvents: 'none',
  });
  document.body.append(ghost);
  return ghost;
}

/** Flies `ghost` from where it is to `point`, shrinking into it, then removes it. */
function flyInto(ghost: HTMLElement, box: DOMRect, from: { x: number; y: number }, point: { x: number; y: number }): Promise<void> {
  if (reduceMotion.matches) {
    ghost.remove();
    return Promise.resolve();
  }
  const dx = point.x - (box.left + box.width / 2);
  const dy = point.y - (box.top + box.height / 2);
  const animation = ghost.animate(
    [
      { transform: `translate(${from.x}px, ${from.y}px) scale(1.04)`, opacity: 1 },
      { transform: `translate(${dx}px, ${dy}px) scale(0.18)`, opacity: 0.2 },
    ],
    { duration: 520, easing: 'cubic-bezier(0.55, 0, 0.3, 1)', fill: 'forwards' },
  );
  return animation.finished.then(() => ghost.remove());
}

export function makeDraggable(source: HTMLElement, options: () => DragOptions): void {
  source.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    const opts = options();
    const start = { x: event.clientX, y: event.clientY };
    const box = source.getBoundingClientRect();
    let ghost: HTMLElement | null = null;
    let over: DropTarget | null = null;
    let offset = { x: 0, y: 0 };
    source.setPointerCapture(event.pointerId);

    // A finger gets more room before a drag starts, so a swipe the page takes over for scrolling shows no copy.
    const threshold = event.pointerType === 'touch' ? 10 : 4;

    const move = (moved: PointerEvent) => {
      offset = { x: moved.clientX - start.x, y: moved.clientY - start.y };
      if (!ghost && Math.hypot(offset.x, offset.y) > threshold) {
        ghost = makeGhost(source, box);
        source.classList.add('is-dragged');
        opts.onStart?.();
      }
      if (!ghost) return;
      ghost.style.transform = `translate(${offset.x}px, ${offset.y}px) scale(1.04)`;
      const target = opts.targets.find((candidate) => candidate.contains(moved.clientX, moved.clientY)) ?? null;
      if (target !== over) {
        over?.leave?.();
        over = target;
        over?.enter?.();
      }
    };

    const end = (ended: PointerEvent) => {
      source.removeEventListener('pointermove', move);
      source.removeEventListener('pointerup', end);
      source.removeEventListener('pointercancel', end);
      if (!ghost) {
        // A tap: the thing goes to its target by itself.
        const target = opts.tapTarget;
        if (ended.type !== 'pointerup' || !target) return;
        opts.onStart?.();
        const flying = makeGhost(source, box);
        void flyInto(flying, box, { x: 0, y: 0 }, target.point()).then(() => {
          target.drop();
          opts.onEnd?.();
        });
        return;
      }
      const target = ended.type === 'pointerup' ? over : null;
      over?.leave?.();
      source.classList.remove('is-dragged');
      const dragged = ghost;
      if (target) {
        target.drop();
        void flyInto(dragged, box, offset, target.point()).then(() => opts.onEnd?.());
        return;
      }
      // Missed: back where it came from. Cancelled, as when the page took the touch to scroll: gone at once.
      if (reduceMotion.matches || ended.type === 'pointercancel') dragged.remove();
      else {
        dragged
          .animate([{ transform: `translate(${offset.x}px, ${offset.y}px)` }, { transform: 'translate(0, 0)', opacity: 0.4 }], {
            duration: 320,
            easing: 'cubic-bezier(0.16, 1, 0.3, 1)',
          })
          .finished.then(() => dragged.remove());
      }
      opts.onEnd?.();
    };

    source.addEventListener('pointermove', move);
    source.addEventListener('pointerup', end);
    source.addEventListener('pointercancel', end);
  });
}
