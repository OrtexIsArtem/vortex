// "Point at the notch": the room the window takes comes first, its outline drawn faintly and the vortex pouring into
// the notch, so it is clear something will happen there. When the room and its text pin, the window opens out of the
// notch on its own spring, and a stretch of scroll later it folds back. The scroll only starts and ends that spring,
// as hover and clicks do, so the window never stops half open; when to do which lives in OpenGate.
import { OpenGate } from '../lib/open-gate';
import { close, isWindowOpen, open, windowOpenedBy } from './notch';
import { drawCurve, drawStreaks, type Funnel } from './vortex-art';

const section = document.querySelector<HTMLElement>('[data-open-section]');
const track = section?.querySelector<HTMLElement>('[data-open-scene]');
const pinned = section?.querySelector<HTMLElement>('[data-open-pinned]');
const stage = section?.querySelector<HTMLElement>('[data-open-stage]');
const canvas = section?.querySelector<HTMLCanvasElement>('[data-open-vortex]');
const context = canvas?.getContext('2d');

if (section && track && pinned && stage && canvas && context) {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let frame = 0;
  let closingHere = false;

  const gate = new OpenGate({
    // Just after the scene pins, and just before it moves on.
    openAt: 0.04,
    closeAt: 0.97,
    settle: 70,
    open: () => open('scroll'),
    close: () => {
      if (!isWindowOpen() || windowOpenedBy() !== 'scroll') return;
      closingHere = true;
      close();
      closingHere = false;
    },
    setTimer: (run, ms) => window.setTimeout(run, ms),
    clearTimer: (id) => window.clearTimeout(id),
  });

  /** Where the scroll is over the pinned stretch: below 0 before the scene pins, above 1 once it has moved on. */
  const position = () => {
    const box = track.getBoundingClientRect();
    return -box.top / Math.max(1, box.height - pinned.offsetHeight);
  };

  // Closed by the visitor (Esc, a click outside or on the notch, a drop): the scene leaves it shut.
  document.addEventListener('vx:close', () => {
    if (!closingHere) gate.closedByVisitor();
  });

  const request = () => {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      gate.update(position());
    });
  };
  window.addEventListener('scroll', request, { passive: true });
  window.addEventListener('resize', request);
  request();

  // The vortex in the room: it runs while the room is on screen and the window is shut, and draws nothing otherwise.
  // It moves only while the visitor scrolls, and a few seconds after: left alone, it settles on the still vortex, as
  // with less motion, so nothing on the page moves by itself for long.
  let width = 0;
  let height = 0;
  let notchHeight = 32;
  let onScreen = false;
  let windowShows = false;
  let phase = 0;
  let last = 0;
  let loop = 0;
  let still = reduceMotion;
  let settleTimer = 0;

  const size = () => {
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    width = stage.clientWidth;
    height = stage.clientHeight;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    notchHeight = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--notch-h')) || 32;
  };

  const paint = () => {
    context.clearRect(0, 0, width, height);
    const funnel: Funnel = { cx: width / 2, cy: notchHeight / 2, width, height };
    if (still) {
      // At rest: a still vortex, the welcome's curves on their way into the notch.
      context.lineWidth = 1;
      for (let i = 0; i < 18; i++) drawCurve(context, funnel, i, 18, 0.7, 0.8);
      return;
    }
    drawStreaks(context, funnel, { count: 20, strength: 0.8, phase, reach: Math.min(width * 0.5, 640) });
  };

  const tick = (now: number) => {
    loop = 0;
    const dt = last ? Math.min(0.05, (now - last) / 1000) : 0;
    last = now;
    phase += dt * 0.32;
    paint();
    if (onScreen && !windowShows && !still) loop = requestAnimationFrame(tick);
    else last = 0;
  };

  const run = () => {
    if (still) {
      paint();
      return;
    }
    if (!loop && onScreen && !windowShows) loop = requestAnimationFrame(tick);
  };

  /** The visitor is scrolling here: the streaks flow, until they have been still for a while. */
  const stir = () => {
    if (reduceMotion || !onScreen) return;
    still = false;
    window.clearTimeout(settleTimer);
    settleTimer = window.setTimeout(() => {
      still = true;
      run();
    }, 4000);
    run();
  };
  window.addEventListener('scroll', stir, { passive: true });

  new IntersectionObserver(([entry]) => {
    onScreen = entry?.isIntersecting ?? false;
    if (onScreen) stir();
    else run();
  }).observe(stage);

  document.addEventListener('vx:open', () => {
    windowShows = true;
    section.classList.add('is-window-open');
  });
  document.addEventListener('vx:close', () => {
    windowShows = false;
    section.classList.remove('is-window-open');
    run();
  });

  new ResizeObserver(() => {
    size();
    paint();
  }).observe(stage);
  size();
  paint();
}
