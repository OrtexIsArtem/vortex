// The Screen Text chapter's scene (components/scenes/ScreenTextScene.astro), as the app's utility runs
// (Packages/Features/ScreenText/docs/behavior.md): Copy Text freezes the screen and the notch says "Screen Text · Esc";
// a frame drawn over it is read once the pointer lets go, its lines go on the visitor's clipboard and the notch says
// how many. Esc ends it at every step before that. Visitors who only watch get it on a loop, a drawn pointer framing
// the log, and nothing goes on their clipboard; any touch hands the scene to them.
import { framedLines, frameBetween, minFrame, type Box } from '../lib/screen-text';
import { record } from './clipboard';
import { appLang, copy } from './copy';
import { setIndicator } from './notch';

type Phase = 'idle' | 'frozen' | 'drawing' | 'reading';

/** How long the notch shows what came of a capture, as the app's message does. */
const messageTime = 1500;
/** How long the hint says it's reading before the frozen screen goes. */
const readTime = 450;

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
/** An ease-in-out, as a hand drags. */
const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const wait = (ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms));

/** Calls `step` with the eased progress, 0 to 1, every frame for `ms`; stops early once `alive` says so. */
function tween(ms: number, step: (t: number) => void, alive: () => boolean): Promise<void> {
  return new Promise((resolve) => {
    const start = performance.now();
    const frame = (now: number) => {
      if (!alive()) return resolve();
      const progress = Math.min(1, (now - start) / ms);
      step(ease(progress));
      if (progress < 1) requestAnimationFrame(frame);
      else resolve();
    };
    requestAnimationFrame(frame);
  });
}

/** Puts the visitor's lines on their clipboard; called within their press, the only time browsers let a page copy. */
async function writeClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

export function mountScreenText(scene: HTMLElement): void {
  const part = <T extends Element>(selector: string) => scene.querySelector<T>(selector);
  const screen = part<HTMLElement>('[data-st-screen]');
  const freeze = part<HTMLElement>('[data-st-freeze]');
  const frame = part<HTMLElement>('[data-st-frame]');
  const pointer = part<SVGElement>('[data-st-pointer]');
  const hint = part<HTMLElement>('[data-st-hint]');
  const auto = part<HTMLButtonElement>('[data-st-auto]');
  const copyButton = part<HTMLButtonElement>('[data-st-capture]');
  const again = part<HTMLButtonElement>('[data-st-again]');
  const status = part<HTMLElement>('[data-st-status]');
  if (!screen || !freeze || !frame || !pointer || !hint || !auto || !copyButton || !again || !status) return;

  const s = copy.screenTextChapter;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let phase: Phase = 'idle';
  let rect: Box = { x: 0, y: 0, w: 0, h: 0 };
  /** Where the visitor's pointer started a frame, while they draw one. */
  let origin: { x: number; y: number } | null = null;
  /** Which step of a capture is current: Esc, a frame of the visitor's, a pause or leaving the screen stops the one
   * under way. */
  let turn = 0;
  /** The visitor's lines are on their way to the clipboard: the copy is made, so Esc comes too late for it. */
  let copying = false;
  /** The visitor has the scene: the loop waits until the scene has left the screen with their focus out of it. */
  let touched = false;
  /** The visitor paused the demo: it doesn't go round by itself again. */
  let paused = false;
  /** Something has played, so Again has something to play again. */
  let played = false;
  /** The loop is going round. */
  let looping = false;
  /** The moment between the scene coming into view and the loop starting. */
  let autoTimer = 0;
  let autoRun = 0;
  let readTimer = 0;
  let messageTimer = 0;
  let statusTimer = 0;
  /** What the button under the scene offers. */
  let offer: 'pause' | 'again' | null = null;

  /** The text on the screen line by line, each with the box of its words in the screen's coordinates; `only` picks
   * some of the lines. */
  const screenLines = (only = '[data-st-line]') => {
    const box = screen.getBoundingClientRect();
    const range = document.createRange();
    return [...scene.querySelectorAll<HTMLElement>(only)].map((element) => {
      range.selectNodeContents(element);
      const r = range.getBoundingClientRect();
      return { box: { x: r.left - box.left, y: r.top - box.top, w: r.width, h: r.height }, text: element.textContent ?? '' };
    });
  };

  /** The frame the demo and Frame the log for me draw: the log's lines, with a little room around them. */
  const logFrame = (): Box => {
    const boxes = screenLines('[data-st-log]').map((line) => line.box);
    const x = Math.max(2, Math.min(...boxes.map((box) => box.x)) - 10);
    const y = Math.max(2, Math.min(...boxes.map((box) => box.y)) - 7);
    const right = Math.min(screen.clientWidth - 2, Math.max(...boxes.map((box) => box.x + box.w)) + 10);
    const bottom = Math.min(screen.clientHeight - 2, Math.max(...boxes.map((box) => box.y + box.h)) + 7);
    return { x, y, w: right - x, h: bottom - y };
  };

  /** Tells a screen reader, once and politely, what the visitor's own action did; the loop is never announced. */
  const say = (text: string, lang?: string) => {
    window.clearTimeout(statusTimer);
    status.textContent = '';
    // Empty for a moment first, so the same words said twice are heard twice.
    statusTimer = window.setTimeout(() => {
      if (lang) status.lang = lang;
      else status.removeAttribute('lang');
      status.textContent = text;
    }, 100);
  };

  const words = (...texts: string[]) => texts.map((text) => ({ kind: 'text' as const, text }));

  /** The notch while the screen is frozen: which feature froze it, and that Esc leaves. */
  const showFrozen = () => {
    window.clearTimeout(messageTimer);
    setIndicator('screentext', { left: words(s.label), right: words(s.esc), priority: 30 });
  };

  /** What came of a capture, beside the closed notch for about 1.5 s; a new message takes the place of the last. It
   * comes before the timer's and the shelf's, after a key waiting for its Allow, as in the app. */
  const showMessage = (left: string, right?: string) => {
    window.clearTimeout(messageTimer);
    setIndicator('screentext', { left: words(left), right: right ? words(right) : [], priority: 15 });
    messageTimer = window.setTimeout(() => setIndicator('screentext', null), messageTime);
  };

  /** The button under the scene: Pause while the demo goes round by itself, Again once it rests. */
  const offerSlot = (next: typeof offer) => {
    offer = next;
    again.textContent = next === 'pause' ? copy.chapter.pause : s.replay;
    again.classList.toggle('is-shown', next !== null);
  };

  /** Brings the scene in line with who has it, and the button under it with the loop; that button never changes under
   * the visitor's focus: only pressing it does. */
  const sync = () => {
    scene.classList.toggle('is-theirs', touched);
    if (document.activeElement === again) return;
    if ((looping || autoTimer) && !touched && !paused && !reduceMotion) offerSlot('pause');
    else offerSlot(played && phase === 'idle' && !looping ? 'again' : null);
  };

  /** `handOff`: the caller puts the focus where it belongs next. */
  const setPhase = (next: Phase, handOff = false) => {
    phase = next;
    scene.classList.toggle('is-frozen', next !== 'idle');
    scene.classList.toggle('is-drawing', next === 'drawing' || next === 'reading');
    hint.textContent = next === 'reading' ? s.reading : s.frameHint;
    if (next === 'idle') {
      scene.classList.remove('is-framing-for-me');
      pointer.classList.remove('is-shown');
    }
    // A part that goes away never takes the focus with it: it lands on Copy Text, where a capture starts again.
    const focused = document.activeElement;
    if (!handOff && focused instanceof HTMLElement && screen.contains(focused) && !focused.getClientRects().length) {
      copyButton.focus({ preventScroll: true });
    }
    sync();
  };

  const drawFrame = () => {
    frame.style.left = `${rect.x}px`;
    frame.style.top = `${rect.y}px`;
    frame.style.width = `${rect.w}px`;
    frame.style.height = `${rect.h}px`;
    frame.style.setProperty('--mark', `${Math.min(12, rect.w / 3, rect.h / 3)}px`);
  };

  const placePointer = (x: number, y: number) => {
    pointer.style.transform = `translate(${x - 12}px, ${y - 12}px)`;
  };

  /** Freezes the screen. The visitor's own press moves the focus to Frame the log for me and says what to do. */
  const freezeScreen = (byVisitor: boolean) => {
    window.clearTimeout(autoTimer);
    autoTimer = 0;
    played = true;
    turn++;
    showFrozen();
    setPhase('frozen', byVisitor);
    if (byVisitor) {
      auto.focus();
      say([s.label, s.frameHint, s.escHint].join('. '), appLang);
    }
  };

  /** Ends a capture with nothing read, said or copied. The visitor's own Esc puts the focus back on Copy Text, and
   * what the status said about the frozen screen goes quietly with it. */
  const cancel = (byVisitor = false) => {
    turn++;
    origin = null;
    window.clearTimeout(readTimer);
    window.clearTimeout(statusTimer);
    status.textContent = '';
    setIndicator('screentext', null);
    if (byVisitor) copyButton.focus();
    setPhase('idle', byVisitor);
  };

  /** Reads the frame once the drag ends: the frame stays and the hint says it's reading, then the frozen screen goes
   * and the notch says what came of it. The visitor's lines set off for the clipboard at once, within the press that
   * let go, so from here Esc comes too late for them. */
  const read = (found: string[], byVisitor: boolean) => {
    const current = ++turn;
    const text = found.join('\n');
    const written = byVisitor && found.length ? writeClipboard(text) : null;
    copying = written !== null;
    setPhase('reading', true);
    readTimer = window.setTimeout(
      () => {
        if (current !== turn) return;
        copying = false;
        const focusOnScreen = screen.contains(document.activeElement);
        setPhase('idle', true);
        if (byVisitor && focusOnScreen) copyButton.focus({ preventScroll: true });
        if (!found.length) {
          // Nothing to copy: the clipboard stays as it was.
          showMessage(s.noText);
          if (byVisitor) say(s.noText, appLang);
        } else if (!written) {
          // The demo shows the app's message and leaves the visitor's clipboard alone.
          showMessage(s.copied, s.lines(found.length));
        } else {
          void written.then((ok) => {
            if (!ok) {
              // The browser kept its clipboard to itself: nothing was copied, so nothing says it was.
              setIndicator('screentext', null);
              window.clearTimeout(statusTimer);
              status.textContent = '';
              return;
            }
            showMessage(s.copied, s.lines(found.length));
            // The copy is the visitor's own, and the page's clipboard history keeps it, as Clipboard does in the app.
            record(text, s.app);
            say(`${s.copied}. ${s.lines(found.length)}`, appLang);
          });
        }
      },
      reduceMotion ? 250 : readTime,
    );
  };

  /** A drawn pointer drags a frame over the log, as a hand would: in from the side, a press, a drag. It says whether
   * it got there, or something stopped it on the way. */
  const drag = async () => {
    const current = turn;
    const alive = () => current === turn;
    const goal = logFrame();
    if (reduceMotion) {
      rect = goal;
      drawFrame();
      setPhase('drawing', true);
      return true;
    }
    const from = { x: goal.x - 44, y: goal.y - 30 };
    placePointer(from.x, from.y);
    pointer.classList.add('is-shown');
    await tween(520, (t) => placePointer(lerp(from.x, goal.x, t), lerp(from.y, goal.y, t)), alive);
    if (!alive()) return false;
    await wait(140);
    if (!alive()) return false;
    rect = { x: goal.x, y: goal.y, w: 0, h: 0 };
    drawFrame();
    setPhase('drawing', true);
    await tween(
      950,
      (t) => {
        const x = lerp(goal.x, goal.x + goal.w, t);
        const y = lerp(goal.y, goal.y + goal.h, t);
        placePointer(x, y);
        rect = { x: goal.x, y: goal.y, w: x - goal.x, h: y - goal.y };
        drawFrame();
      },
      alive,
    );
    return alive();
  };

  // The visitor's own frame, drawn with the pointer or a finger.
  freeze.addEventListener('pointerdown', (event) => {
    if ((event.target as Element).closest('button') || phase === 'reading' || !event.isPrimary) return;
    touched = true;
    turn++;
    pointer.classList.remove('is-shown');
    scene.classList.remove('is-framing-for-me');
    const box = screen.getBoundingClientRect();
    origin = { x: event.clientX - box.left, y: event.clientY - box.top };
    rect = { ...origin, w: 0, h: 0 };
    freeze.setPointerCapture(event.pointerId);
    setPhase('drawing', true);
    drawFrame();
  });
  freeze.addEventListener('pointermove', (event) => {
    if (!origin) return;
    const box = screen.getBoundingClientRect();
    rect = frameBetween(origin, { x: clamp(event.clientX - box.left, 0, box.width), y: clamp(event.clientY - box.top, 0, box.height) });
    drawFrame();
  });
  freeze.addEventListener('pointerup', () => {
    if (!origin) return;
    origin = null;
    // A frame under 8 px either way is a click, which ends the capture quietly, as in the app.
    if (rect.w < minFrame || rect.h < minFrame) cancel(true);
    else read(framedLines(rect, screenLines()), true);
  });
  // A finger the page took for a scroll draws nothing; the screen stays frozen for the next try.
  freeze.addEventListener('pointercancel', () => {
    if (!origin) return;
    origin = null;
    setPhase('frozen', true);
  });

  copyButton.addEventListener('click', () => {
    touched = true;
    if (phase === 'idle') freezeScreen(true);
    // A press while a capture is under way starts nothing, as in the app; it brings the visitor to the one there is.
    else if (phase === 'frozen') {
      auto.focus();
      say([s.label, s.frameHint, s.escHint].join('. '), appLang);
    }
  });

  // Frames the log at once, for the keyboard and for anyone who doesn't drag; the copy sets off within this press.
  auto.addEventListener('click', () => {
    if (phase !== 'frozen') return;
    touched = true;
    turn++;
    rect = logFrame();
    drawFrame();
    scene.classList.add('is-framing-for-me');
    read(framedLines(rect, screenLines()), true);
  });

  // Esc leaves the frozen screen at every step until the lines are read, and only from inside the scene: the rest of
  // the page keeps its keys.
  scene.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || phase === 'idle' || copying) return;
    event.preventDefault();
    cancel(true);
  });

  /** One pass of the demo: Copy Text pressed, a drawn pointer framing the log, the notch's "Copied · 3 lines". It says
   * whether it played to the end. */
  const pass = async (alive: () => boolean) => {
    // Asked as a call: the phase changes under the waits, which a plain comparison would take as settled.
    const at = (expected: Phase) => alive() && phase === expected;
    copyButton.classList.add('is-pressed');
    await wait(200);
    copyButton.classList.remove('is-pressed');
    if (!at('idle')) return false;
    freezeScreen(false);
    await wait(reduceMotion ? 300 : 520);
    if (!at('frozen') || !(await drag()) || !alive()) return false;
    read(framedLines(rect, screenLines()), false);
    await wait((reduceMotion ? 250 : readTime) + messageTime);
    return at('idle');
  };

  // Visitors who only watch get it on a loop: a moment after the scene comes into view it plays, rests, and plays
  // again. Any touch hands the scene to the visitor until it leaves the screen, and Pause stops it for good. With Reduce
  // Motion it plays once.
  const autoplay = async () => {
    const run = ++autoRun;
    const alive = () => run === autoRun && !touched && !paused;
    looping = true;
    played = true;
    sync();
    try {
      while ((await pass(alive)) && !reduceMotion) {
        await wait(3800);
        if (!alive()) return;
      }
    } finally {
      if (run === autoRun) looping = false;
      sync();
    }
  };

  /** Pause: no more rounds, a capture under way ends unread, and the scene rests; the button then offers Again. */
  const pause = () => {
    paused = true;
    autoRun++;
    looping = false;
    window.clearTimeout(autoTimer);
    autoTimer = 0;
    if (phase !== 'idle' && !copying) cancel();
    offerSlot('again');
  };

  again.addEventListener('click', () => {
    if (offer === 'pause') {
      pause();
      return;
    }
    // Again: one pass of the demo, for the visitor who asked for it.
    if (copying) return;
    touched = true;
    if (phase !== 'idle') cancel();
    const run = ++autoRun;
    void pass(() => run === autoRun);
  });
  again.addEventListener('blur', sync);

  // Any touch hands the scene to the visitor, a capture under way with it: a frame the demo was drawing goes, and the
  // frozen screen waits for theirs. The button under the scene is the exception: only its click changes anything.
  const takeOver = (event: Event) => {
    if (event.target instanceof Node && again.contains(event.target)) return;
    if (!touched && !copying && (phase === 'drawing' || phase === 'reading')) {
      turn++;
      window.clearTimeout(readTimer);
      setPhase('frozen', true);
    }
    touched = true;
    window.clearTimeout(autoTimer);
    autoTimer = 0;
    sync();
  };
  scene.addEventListener('pointerdown', takeOver);
  scene.addEventListener('keydown', takeOver);
  scene.addEventListener('focusin', takeOver);

  new IntersectionObserver(
    ([entry]) => {
      window.clearTimeout(autoTimer);
      autoTimer = 0;
      // Off screen it rests: a capture ends, as another app coming to the front ends it in the app, and the visitor's
      // turn ends unless their focus is still in the scene.
      if (!entry?.isIntersecting) {
        autoRun++;
        looping = false;
        if (phase !== 'idle' && !copying) cancel();
        if (!scene.contains(document.activeElement)) touched = false;
        sync();
        return;
      }
      if (entry.intersectionRatio >= 0.6 && !looping && !touched && !paused && phase === 'idle') {
        autoTimer = window.setTimeout(() => {
          autoTimer = 0;
          if (!looping && !touched && !paused && phase === 'idle') void autoplay();
          else sync();
        }, 1000);
      }
      sync();
    },
    { threshold: [0, 0.6] },
  ).observe(scene);
}
