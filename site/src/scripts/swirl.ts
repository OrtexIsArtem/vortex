// The hero's vortex: thin curves spiral into the notch, as in the app's welcome (WelcomePage.swift, SpiralCurve), then
// light comes on from the notch and the text appears. Afterwards the notch pulls: as the pointer comes near it, thin
// streaks spiral down into it, faster the closer the pointer is. Nothing is drawn while the pointer is away or the
// window is open.
import { endIntro, setIntro } from './notch';
import { drawCurve, drawStreaks, type Funnel } from './vortex-art';

const canvas = document.querySelector<HTMLCanvasElement>('[data-swirl]');
const hero = document.querySelector<HTMLElement>('[data-hero]');
const context = canvas?.getContext('2d');

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

function cubicBezier(x1: number, y1: number, x2: number, y2: number): (x: number) => number {
  const cx = 3 * x1;
  const bx = 3 * (x2 - x1) - cx;
  const ax = 1 - cx - bx;
  const cy = 3 * y1;
  const by = 3 * (y2 - y1) - cy;
  const ay = 1 - cy - by;
  const sampleX = (t: number) => ((ax * t + bx) * t + cx) * t;
  const sampleY = (t: number) => ((ay * t + by) * t + cy) * t;
  const slopeX = (t: number) => (3 * ax * t + 2 * bx) * t + cx;
  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const error = sampleX(t) - x;
      const slope = slopeX(t);
      if (Math.abs(error) < 1e-5 || Math.abs(slope) < 1e-6) break;
      t -= error / slope;
    }
    return sampleY(clamp(t, 0, 1));
  };
}

/** SwiftUI's easeInOut, which the app's welcome uses. */
const easeInOut = cubicBezier(0.42, 0, 0.58, 1);

const introDuration = 2200;
/** When the light comes on, as a share of the intro: the notch has just shown. */
const lightAt = 0.68;
/** How far the pull reaches from the notch, in px. */
const pullReach = 520;
const streakCount = 22;

if (canvas && context && hero) {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  let width = 0;
  let height = 0;
  let notchHeight = 32;
  let introCount = 48;

  let introProgress = 0;
  let introStart = 0;
  let introDone = false;
  let lit = false;

  /** How strongly the streaks show, 0 to 1, and where along their spirals they are. */
  let flow = 0;
  let flowTarget = 0;
  let flowPhase = 0;
  let proximity = 0;
  let windowOpen = false;
  let last = 0;
  let frame = 0;
  /** Whether the canvas holds anything. A blank one is hidden, so the full-screen layer costs nothing, and isn't cleared again. */
  let painted = false;
  let shownOpacity = '';

  const resize = () => {
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    notchHeight = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--notch-h')) || 32;
    introCount = width < 768 ? 24 : 48;
  };

  const render = () => {
    const fade = 1 - clamp(window.scrollY / (height * 0.7), 0, 1);
    const draws = fade > 0 && (!introDone || flow > 0.004);
    if (painted) context.clearRect(0, 0, width, height);
    if (draws !== painted) canvas.style.visibility = draws ? 'visible' : 'hidden';
    painted = draws;
    if (!draws) return;
    const opacity = fade.toFixed(3);
    if (opacity !== shownOpacity) canvas.style.opacity = shownOpacity = opacity;
    const funnel: Funnel = { cx: width / 2, cy: notchHeight / 2, width, height };
    if (!introDone) {
      context.lineWidth = 1;
      const p = easeInOut(introProgress);
      for (let i = 0; i < introCount; i++) drawCurve(context, funnel, i, introCount, p);
    } else {
      drawStreaks(context, funnel, {
        count: streakCount,
        strength: flow,
        phase: flowPhase,
        reach: Math.min(Math.max(width, height) * 0.5, 720),
      });
    }
  };

  const light = () => {
    if (lit) return;
    lit = true;
    hero.classList.add('is-lit');
    document.documentElement.classList.add('is-lit');
  };

  const finishIntro = () => {
    introProgress = 1;
    introDone = true;
    setIntro(1);
    endIntro();
    light();
  };

  const tick = (now: number) => {
    frame = 0;
    const dt = last ? Math.min(0.05, (now - last) / 1000) : 0;
    last = now;
    let busy = false;

    if (!introDone) {
      if (!introStart) introStart = now;
      introProgress = clamp((now - introStart) / introDuration, 0, 1);
      setIntro(easeInOut(introProgress));
      if (introProgress >= lightAt) light();
      if (introProgress >= 1) finishIntro();
      busy = true;
    } else {
      // Gathers as the pointer nears and runs faster; ebbs away as it leaves or the window opens.
      const rate = flowTarget > flow ? 3.5 : 2.4;
      flow += (flowTarget - flow) * (1 - Math.exp(-dt * rate));
      flowPhase += dt * (0.16 + 0.42 * flow);
      if (flowTarget === 0 && flow < 0.004) flow = 0;
      busy = flow > 0 || flowTarget > 0;
    }

    render();
    if (busy) frame = requestAnimationFrame(tick);
    else last = 0;
  };

  const kick = () => {
    if (!frame) frame = requestAnimationFrame(tick);
  };

  const aim = () => {
    const heroShows = window.scrollY < height * 0.7;
    flowTarget = windowOpen || !heroShows ? 0 : Math.pow(proximity, 1.3);
    // Scrolling with nothing drawn and nothing to draw costs no frame.
    if (flowTarget > 0 || flow > 0 || painted) kick();
  };

  resize();

  // A visitor who arrives mid-page, or asks for less motion, gets the settled frame at once.
  if (reduceMotion || window.scrollY > 40) {
    finishIntro();
    render();
  } else {
    // Anything the visitor does finishes the intro: the page shouldn't keep them waiting.
    const skip = () => {
      if (!introDone) finishIntro();
    };
    window.addEventListener('keydown', skip, { once: true });
    window.addEventListener('wheel', skip, { once: true, passive: true });
    window.addEventListener('touchstart', skip, { once: true, passive: true });
    document.querySelector('.vx-notch')?.addEventListener('pointerenter', skip, { once: true });
    kick();
  }

  window.addEventListener('resize', () => {
    resize();
    render();
  });
  window.addEventListener('scroll', () => (introDone ? aim() : kick()), { passive: true });

  if (!reduceMotion) {
    window.addEventListener('pointermove', (event) => {
      if (event.pointerType !== 'mouse' || !introDone) return;
      const dx = event.clientX - width / 2;
      const dy = (event.clientY - notchHeight / 2) * 1.3;
      proximity = clamp(1 - Math.hypot(dx, dy) / pullReach, 0, 1);
      aim();
    });
    document.documentElement.addEventListener('pointerleave', () => {
      proximity = 0;
      aim();
    });
    document.addEventListener('vx:open', () => {
      windowOpen = true;
      aim();
    });
    document.addEventListener('vx:close', () => {
      windowOpen = false;
      aim();
    });
  }
}
