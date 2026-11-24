// The page's notch, which behaves as the app's does (Packages/Shell/docs/behavior.md): hover opens it after 0.3 s,
// leaving closes it after 0.5 s, a click opens or closes it, Esc and a click outside close it. Scenes further down
// the page show their state in its ears and flash it.
import { iconSvg, type IconName } from '../lib/icons';
import { hangingPath, metrics, windowScale as fitWindow, type Outline } from '../lib/shape';
import { SpringGroup, springs } from './spring';

export type EarItem =
  | { kind: 'ring'; value: number }
  | { kind: 'icon'; name: IconName }
  | { kind: 'text'; text: string; mono?: boolean };

export type FlashColor = 'glow-1' | 'glow-2' | 'white' | 'alarm';

/** What a feature shows beside the closed notch; the higher priority stands nearer the notch. */
export interface Indicator {
  left?: EarItem[];
  right?: EarItem[];
  priority: number;
}

type OpenReason = 'hover' | 'click' | 'scroll';

/** While something is dragged over the page the notch opens into a drop zone, brighter with the drag over it. */
export type DropState = 'off' | 'shown' | 'hover';

/** The silhouette as the spring moves it: its outline, how far its middle stands right of the notch's (the open window
 *  grows only to the right), and the window's scale inside it. */
interface Frame extends Outline {
  shift: number;
  scale: number;
}

const glowColors: Record<FlashColor, string> = {
  'glow-1': 'rgb(90 200 250)',
  'glow-2': 'rgb(74 222 128)',
  white: 'rgb(255 255 255)',
  alarm: 'rgb(255 159 67)',
};

/** One flash of the app's NotchGlowView: up, half down, up again, out — 1.5 s. */
const flashKeyframes: Keyframe[] = [
  { opacity: 0, easing: 'ease-in-out' },
  { opacity: 1, offset: 0.16 / 1.5, easing: 'ease-in-out' },
  { opacity: 0.35, offset: 0.44 / 1.5, easing: 'ease-in-out' },
  { opacity: 1, offset: 0.6 / 1.5, easing: 'ease-in-out' },
  { opacity: 0 },
];
const flashDuration = 1500;

/** The row the closed notch grows down by on a narrow screen, for words that don't fit beside it. */
const rowHeight = 24;

const hoverDelay = 300;
const leaveDelay = 500;
/** A window opened by hover or click closes once the page scrolls this far. */
const scrollToClose = 160;

const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

const root = document.querySelector<HTMLElement>('[data-vx]');
if (!root) throw new Error('The notch is missing from the page');

function part<T extends Element>(selector: string): T {
  const element = root!.querySelector<T>(selector);
  if (!element) throw new Error(`The notch has no ${selector}`);
  return element;
}

const button = part<HTMLButtonElement>('.vx-notch');
const win = part<HTMLElement>('.vx-window');
const fill = part<SVGPathElement>('.vx-shape__fill');
const flashFill = part<SVGPathElement>('.vx-shape__flash');
const edge = part<SVGPathElement>('.vx-shape__edge');
const core = part<SVGPathElement>('.vx-shape__core');
const lens = part<SVGCircleElement>('.vx-shape__lens');
const glow = part<HTMLElement>('.vx-glow');
const halo = part<SVGPathElement>('.vx-glow__halo path');
const earLeft = part<HTMLElement>('[data-ear="left"]');
const earRight = part<HTMLElement>('[data-ear="right"]');
const earRow = part<HTMLElement>('[data-ear="row"]');
const dropZone = part<HTMLElement>('.vx-drop');
/** What the intro fades in. */
const introParts: (HTMLElement | SVGElement)[] = [button, ...root.querySelectorAll<SVGElement>('.vx-layer')];
/** The menu bar keeps its items clear of the ears, so it reads their width too. */
const menubar = document.querySelector<HTMLElement>('[data-menubar]');

const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
const labels = { open: button.dataset.labelOpen ?? '', close: button.dataset.labelClose ?? '' };

let notchW = 186;
let notchH = 32;
/** The open window is scaled down to fit narrow screens. */
let windowScale = 1;
/** Room the open window takes beyond its regular width, at its right: Home's utilities strip while it is out. */
let extraWidth = 0;
/** The scale the window was last drawn at. */
let drawnScale = Number.NaN;
/** What Esc puts away inside the open window before it closes the window. */
let escapeInside: (() => boolean) | null = null;
let earW = 0;
/** The row under the closed notch, as wide as its words and their padding; 0 while the words fit beside the notch. */
let rowW = 0;
let rowH = 0;
let isOpen = false;
let openedBy: OpenReason | null = null;
let scrollAtOpen = 0;
let hoverTimer = 0;
let leaveTimer = 0;
/** After the window closes under the pointer, hovering counts again only once the pointer has left. */
let hoverSpent = false;
let glowAnimation: Animation | null = null;
let alarmOn = false;
/** A one-off longer wait before the window may close, after a drag that ended outside it. */
let leaveOverride = 0;
const indicators = new Map<string, Indicator>();
let dropState: DropState = 'off';

function readSizes(): void {
  const style = getComputedStyle(root!);
  notchW = parseFloat(style.getPropertyValue('--notch-w')) || 186;
  notchH = parseFloat(style.getPropertyValue('--notch-h')) || 32;
  // Narrow screens scale the window to fit; short ones too, leaving room for the text under it.
  windowScale = fitWindow(window.innerWidth, window.innerHeight);
  // On the page's root too: the section that opens the window pins its text just under it.
  document.documentElement.style.setProperty('--window-scale', String(windowScale));
  root!.style.setProperty('--drop-scale', String(dropScale()));
}

function closedOutline(): Frame {
  if (rowH > 0) {
    const width = Math.max(notchW + earW * 2, rowW);
    return { width, height: notchH + rowH, radius: metrics.ears.radius, shoulder: metrics.window.shoulder, shift: 0, scale: windowScale };
  }
  return earW > 0
    ? { width: notchW + earW * 2, height: notchH, radius: metrics.ears.radius, shoulder: metrics.window.shoulder, shift: 0, scale: windowScale }
    : { width: notchW, height: notchH, radius: metrics.notchRadius, shoulder: 0, shift: 0, scale: windowScale };
}

function dropScale(): number {
  return Math.min(1, (window.innerWidth - 32) / 420);
}

function dropOutline(): Frame {
  const s = dropScale();
  return { width: 380 * s, height: 104 * s, radius: 26 * s, shoulder: 10 * s, shift: 0, scale: windowScale };
}

function openOutline(): Frame {
  const { width, height, radius, shoulder } = metrics.window;
  // Grown, the window keeps its left edge, as the app's does; a screen too narrow for the room it took scales it down.
  const s = extraWidth > 0 ? fitWindow(window.innerWidth, window.innerHeight, extraWidth) : windowScale;
  return {
    width: (width + extraWidth) * s,
    height: height * s,
    radius: radius * s,
    shoulder: shoulder * s,
    shift: (extraWidth / 2) * s,
    scale: s,
  };
}

function draw(o: Frame): void {
  const d = hangingPath(o, true, o.shift);
  fill.setAttribute('d', d);
  flashFill.setAttribute('d', d);
  edge.setAttribute('d', hangingPath(o, false, o.shift));

  // How far the window has opened: the notch inside it shrinks to the window's scale, so narrow screens fit. A row of
  // words under the closed notch is no opening.
  const s = o.scale || 1;
  const openHeight = metrics.window.height * s;
  const closedHeight = notchH + rowH;
  const progress = clamp((o.height - closedHeight) / Math.max(1, openHeight - closedHeight), 0, 1);
  const coreW = lerp(notchW, 186 * s, progress);
  const coreH = lerp(notchH, 32 * s, progress);
  core.setAttribute('d', hangingPath({ width: coreW, height: coreH, radius: metrics.notchRadius, shoulder: 0 }));
  lens.setAttribute('cy', (coreH / 2).toFixed(2));

  // The window springs to a smaller scale with its outline when a narrow screen has no room for the strip.
  if (s !== drawnScale) {
    drawnScale = s;
    win.style.transform = `scale(${s})`;
  }
  // The content is clipped to the shape while it grows, as the app clips it (WindowChromeView).
  const local: Outline = { width: o.width / s, height: o.height / s, radius: o.radius / s, shoulder: o.shoulder / s };
  win.style.clipPath = `path('${hangingPath(local, true, metrics.window.width / 2 + o.shift / s)}')`;

  // Closed, the whole silhouette takes the pointer; open, only the notch does, the window takes the rest. On the notch
  // itself: on the root, a custom property would restyle the whole window every frame of the spring.
  button.style.setProperty('--hit-w', `${isOpen ? coreW : o.width}px`);
  button.style.setProperty('--hit-h', `${isOpen ? coreH : o.height}px`);
}

const outline = new SpringGroup<keyof Frame>(closedOutline(), draw);

function sizeGlow(): void {
  const silhouette = closedOutline();
  const { spread, depth } = metrics.glow;
  glow.style.setProperty('--glow-w', `${silhouette.width + spread * 2}px`);
  glow.style.setProperty('--glow-h', `${silhouette.height + depth}px`);
  halo.setAttribute('d', hangingPath(silhouette));
}

function ringSvg(value: number): string {
  const circumference = 2 * Math.PI * 7;
  const lit = circumference * clamp(value, 0, 1);
  return `<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7" fill="none" stroke="#2A2A2E" stroke-width="2"/><circle cx="8" cy="8" r="7" fill="none" stroke="#F5F5F7" stroke-width="2" stroke-linecap="round" stroke-dasharray="${lit.toFixed(2)} ${circumference.toFixed(2)}" transform="rotate(-90 8 8)"/></svg>`;
}

/** Draws `items` in `ear` and answers their width; a dot goes before the item at `separateAt`, if any. */
function renderEar(ear: HTMLElement, items: EarItem[], separateAt = -1): number {
  const row = document.createElement('span');
  row.className = 'vx-ear__row';
  for (const [index, item] of items.entries()) {
    if (index === separateAt) {
      const dot = document.createElement('span');
      dot.className = 'vx-ear__item vx-ear__dot';
      dot.textContent = '·';
      row.append(dot);
    }
    const cell = document.createElement('span');
    cell.className = 'vx-ear__item';
    if (item.kind === 'ring') cell.innerHTML = ringSvg(item.value);
    else if (item.kind === 'icon') cell.innerHTML = iconSvg(item.name, 16);
    else {
      cell.textContent = item.text;
      if (item.mono) cell.classList.add('is-mono');
    }
    row.append(cell);
  }
  ear.replaceChildren(row);
  return items.length ? row.getBoundingClientRect().width : 0;
}

function emit(name: 'vx:open' | 'vx:close'): void {
  document.dispatchEvent(new CustomEvent(name));
}

/**
 * How wide an ear may be. Below 960px the menu bar's buttons stay beside the notch, so an ear stops short of them;
 * wider screens make room themselves: the menu bar's items that would meet an ear drop out (MenuBar.astro).
 */
function earRoom(): number {
  if (!menubar || window.innerWidth >= 960) return Infinity;
  const center = window.innerWidth / 2;
  const brand = menubar.querySelector('.menubar__brand svg')?.getBoundingClientRect().right ?? 0;
  const lefts = [...menubar.querySelectorAll('.menubar__side--end > *')]
    .map((item) => item.getBoundingClientRect())
    .filter((box) => box.width > 0)
    .map((box) => box.left);
  const end = Math.min(window.innerWidth, ...lefts);
  return Math.max(0, Math.min(center - notchW / 2 - brand, end - center - notchW / 2) - 8);
}

const wordsOf = (items: EarItem[]) => items.filter((item) => item.kind === 'text');

/** The most of `items` that fits `room` with every word kept: all of them, then the words alone. Null when a word
 *  doesn't fit even so; icons alone that don't fit leave the ear empty. */
function fitEar(ear: HTMLElement, items: EarItem[], room: number): number | null {
  const words = wordsOf(items);
  for (const attempt of [items, words]) {
    if (!attempt.length) continue;
    const width = renderEar(ear, attempt);
    if (width <= room) return width;
  }
  renderEar(ear, []);
  return words.length ? null : 0;
}

/**
 * Words too wide for the ears, as on a phone, go under the notch instead, in one row: the left side's items, a dot, the
 * right side's ("Screen Text · Esc"); then their words alone; then the left side's words, which say what is going on,
 * cut short only where even they don't fit. Answers the row's width.
 */
function fitRow(left: EarItem[], right: EarItem[], room: number): number {
  const attempts: [EarItem[], EarItem[]][] = [
    [left, right],
    [wordsOf(left), wordsOf(right)],
    [wordsOf(left), []],
  ];
  let width = 0;
  for (const [start, end] of attempts) {
    if (!start.length && !end.length) continue;
    // The dot parts the two sides only when both say something.
    width = renderEar(earRow, [...start, ...end], wordsOf(start).length && wordsOf(end).length ? start.length : -1);
    if (width <= room) return width;
  }
  return Math.min(width, room);
}

/** Tells the menu bar how far the notch reaches to each side: its ears or the row under it, or the open window, which
 *  reaches further right once it has grown there. */
function reachMenubar(): void {
  if (!menubar) return;
  const open = openOutline();
  const closed = Math.max(0, closedOutline().width / 2 - notchW / 2);
  const start = isOpen ? Math.max(0, open.width / 2 - open.shift - notchW / 2) : closed;
  const end = isOpen ? Math.max(0, open.width / 2 + open.shift - notchW / 2) : closed;
  // Only on what reads it: on the page's root, a custom property would restyle the whole page each time it changes.
  menubar.style.setProperty('--ear-w', `${start}px`);
  menubar.style.setProperty('--ear-w-end', `${end}px`);
  menubar.classList.toggle('has-window', isOpen);
  menubar.classList.toggle('has-wide-window', isOpen && extraWidth > 0);
}

/** Shows `left` and `right` beside the closed notch; empty on both sides, the ears fold away. */
function setEars(left: EarItem[], right: EarItem[]): void {
  // The phone's smaller notch has proportionally narrower ears.
  const padding = metrics.ears.padding * Math.min(1, notchW / 186);
  const reach = earRoom();
  const room = reach - padding * 2;
  const leftWidth = fitEar(earLeft, left, room);
  const rightWidth = fitEar(earRight, right, room);
  let content = 0;
  if (leftWidth === null || rightWidth === null) {
    // A word doesn't fit beside the notch: the notch grows down by a row and says it there, the ears' room on each side
    // its limit, so the menu bar's buttons stay clear.
    renderEar(earLeft, []);
    renderEar(earRight, []);
    rowW = Math.ceil(fitRow(left, right, notchW + reach * 2 - padding * 2) + padding * 2);
    rowH = rowHeight;
  } else {
    content = Math.max(leftWidth, rightWidth);
    renderEar(earRow, []);
    rowW = 0;
    rowH = 0;
  }
  earW = content > 0 ? Math.ceil(content + padding * 2) : 0;
  button.style.setProperty('--ear-w', `${earW}px`);
  earRow.style.setProperty('--row-w', `${rowW}px`);
  earRow.style.setProperty('--row-h', `${rowH}px`);
  reachMenubar();
  document.documentElement.classList.toggle('has-ears', earW > 0 || rowH > 0);
  if (isOpen || dropState !== 'off') return;
  if (reduceMotion.matches) outline.set(closedOutline());
  else void outline.to(closedOutline(), springs.ears);
}

/** Puts a feature's indicator beside the notch, or takes it away with null. */
export function setIndicator(id: string, indicator: Indicator | null): void {
  if (indicator) indicators.set(id, indicator);
  else indicators.delete(id);
  showIndicators();
}

function showIndicators(): void {
  const byPriority = [...indicators.values()].sort((a, b) => b.priority - a.priority);
  // The highest priority stands nearest the notch on each side; an indicator's own items keep their order.
  setEars(
    [...byPriority].reverse().flatMap((item) => item.left ?? []),
    byPriority.flatMap((item) => item.right ?? []),
  );
}

export function open(reason: OpenReason): void {
  window.clearTimeout(hoverTimer);
  window.clearTimeout(leaveTimer);
  if (isOpen) {
    // A click on a window that opened by hover keeps it open, as if the click had opened it; a scroll scene takes
    // the window over, so the scrolling it is made of doesn't close it.
    if (reason === 'click' && openedBy === 'hover') openedBy = 'click';
    if (reason === 'scroll') openedBy = 'scroll';
    return;
  }
  isOpen = true;
  openedBy = reason;
  scrollAtOpen = window.scrollY;
  stopAlarm();
  root!.classList.add('is-open', 'hint-seen');
  button.setAttribute('aria-expanded', 'true');
  button.setAttribute('aria-label', labels.close);
  win.inert = false;
  reachMenubar();
  if (reduceMotion.matches) outline.set(openOutline());
  else void outline.to(openOutline(), springs.open);
  emit('vx:open');
}

export function close(): void {
  window.clearTimeout(hoverTimer);
  window.clearTimeout(leaveTimer);
  if (!isOpen) return;
  isOpen = false;
  openedBy = null;
  // Every open starts at the regular size.
  extraWidth = 0;
  hoverSpent = button.matches(':hover');
  if (win.contains(document.activeElement)) button.focus();
  root!.classList.remove('is-open');
  button.setAttribute('aria-expanded', 'false');
  button.setAttribute('aria-label', labels.open);
  win.inert = true;
  reachMenubar();
  if (reduceMotion.matches) outline.set(closedOutline());
  else void outline.to(closedOutline(), springs.close);
  emit('vx:close');
}

/** One flash, or `times` flashes back to back. An alarm going on picks up again once they are over. */
export function flash(color: FlashColor, times = 1): void {
  glow.style.setProperty('--glow', glowColors[color]);
  flashFill.style.setProperty('--glow', glowColors[color]);
  sizeGlow();
  glowAnimation?.cancel();
  if (reduceMotion.matches) {
    // A steady glow instead of blinks.
    glowAnimation = glow.animate([{ opacity: 0 }, { opacity: 0.6, offset: 0.15 }, { opacity: 0.6, offset: 0.75 }, { opacity: 0 }], {
      duration: flashDuration * times,
    });
    return;
  }
  const animation = glow.animate(flashKeyframes, { duration: flashDuration, iterations: times });
  glowAnimation = animation;
  if (alarmOn && Number.isFinite(times)) {
    animation.finished.then(() => {
      if (alarmOn && glowAnimation === animation) playAlarm();
    }, () => {});
  }
  // The notch itself takes on a little of the color, as in NotchEarsView.
  flashFill.animate([{ opacity: 0 }, { opacity: 0.3, offset: 0.12 / 0.72, easing: 'ease-in' }, { opacity: 0 }], {
    duration: 720,
    easing: 'ease-out',
  });
}

let alarmColor: FlashColor = 'alarm';

function playAlarm(): void {
  alarmOn = false;
  flash(alarmColor, reduceMotion.matches ? 1 : Infinity);
  alarmOn = true;
}

/** Flashes again and again until the pointer comes over the notch or the window opens, as time's up does. */
export function alarm(color: FlashColor = 'alarm'): void {
  alarmColor = color;
  if (isOpen) {
    // With the window open it flashes three times and counts as seen.
    alarmOn = false;
    flash(color, 3);
    emitSeen();
    return;
  }
  playAlarm();
}

export function stopAlarm(): void {
  if (!alarmOn) return;
  alarmOn = false;
  glowAnimation?.cancel();
  glowAnimation = null;
  emitSeen();
}

function emitSeen(): void {
  document.dispatchEvent(new CustomEvent('vx:alarm-seen'));
}

/** Opens the notch into a drop zone while something is dragged over the page, as the app's notch does for files. */
export function setDropZone(state: DropState): void {
  if (state === dropState) return;
  const was = dropState;
  dropState = state;
  root!.classList.toggle('is-drop', state !== 'off');
  root!.classList.toggle('is-drop-hover', state === 'hover');
  dropZone.dataset.state = state;
  if (was === 'off') {
    window.clearTimeout(hoverTimer);
    if (isOpen) close();
    if (reduceMotion.matches) outline.set(dropOutline());
    else void outline.to(dropOutline(), springs.open);
  } else if (state === 'off') {
    if (reduceMotion.matches) outline.set(closedOutline());
    else void outline.to(closedOutline(), springs.close);
  }
}

/** Whether a drag at `x`, `y` is over the drop zone. */
export function inDropZone(x: number, y: number): boolean {
  if (dropState === 'off') return false;
  const zone = dropOutline();
  return Math.abs(x - window.innerWidth / 2) <= zone.width / 2 + 24 && y <= zone.height + 32;
}

/** Where things dropped on the notch fly to: its middle, in the viewport. */
export function dropPoint(): { x: number; y: number } {
  return { x: window.innerWidth / 2, y: notchH / 2 };
}

/** The window waits `ms` instead of the usual leave delay the next time the pointer leaves it. */
export function holdOpen(ms: number): void {
  leaveOverride = ms;
}

/**
 * Grows the open window right by `width`, or back to its regular size with 0, as the app's window grows for Home's
 * utilities strip (WindowSize.dock): it keeps its left edge, the content takes the new size at once and the outline
 * follows on the opening's spring. Growing is deliberate: a window the pointer opened no longer closes as it leaves.
 */
export function setExtraWidth(width: number): void {
  if (!isOpen || width === extraWidth) return;
  extraWidth = width;
  if (width > 0 && openedBy === 'hover') {
    openedBy = 'click';
    window.clearTimeout(leaveTimer);
  }
  reachMenubar();
  if (reduceMotion.matches) outline.set(openOutline());
  else void outline.to(openOutline(), springs.open);
}

/** What Esc puts away inside the open window first, as the app's Esc puts Home's utilities strip away before it closes
 *  the window: `handler` answers whether it put something away. */
export function onEscapeInside(handler: () => boolean): void {
  escapeInside = handler;
}

export function isWindowOpen(): boolean {
  return isOpen;
}

/** Who opened the window, or null while it is shut. */
export function windowOpenedBy(): OpenReason | null {
  return openedBy;
}

/** The intro's progress, 0 to 1: the notch fades in over its last stretch, as in the app's welcome. */
export function setIntro(progress: number): void {
  const value = String(clamp((progress - 0.55) / 0.45, 0, 1));
  for (const element of introParts) element.style.setProperty('--intro', value);
}

export function endIntro(): void {
  for (const element of introParts) element.style.setProperty('--intro', '1');
  root!.classList.add('is-ready');
}

function scheduleLeave(): void {
  if (!isOpen || openedBy !== 'hover') return;
  window.clearTimeout(leaveTimer);
  const delay = leaveOverride || leaveDelay;
  leaveOverride = 0;
  leaveTimer = window.setTimeout(() => {
    if (!button.matches(':hover') && !win.matches(':hover')) close();
  }, delay);
}

button.addEventListener('pointerenter', (event) => {
  if (event.pointerType !== 'mouse' || dropState !== 'off') return;
  stopAlarm();
  window.clearTimeout(leaveTimer);
  if (isOpen || hoverSpent) return;
  hoverTimer = window.setTimeout(() => open('hover'), hoverDelay);
});
button.addEventListener('pointermove', (event) => {
  if (event.pointerType === 'mouse') stopAlarm();
});
button.addEventListener('pointerleave', (event) => {
  if (event.pointerType !== 'mouse') return;
  window.clearTimeout(hoverTimer);
  hoverSpent = false;
  scheduleLeave();
});
win.addEventListener('pointerenter', () => window.clearTimeout(leaveTimer));
win.addEventListener('pointerleave', (event) => {
  if (event.pointerType === 'mouse') scheduleLeave();
});

button.addEventListener('click', () => {
  if (dropState !== 'off') return;
  if (!isOpen) open('click');
  else if (openedBy === 'hover') openedBy = 'click';
  else close();
});

// Esc closes the window, after what is out inside it, or else quiets the alarm: a keyboard needs no pointer over the
// notch to say it was seen.
document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (isOpen && escapeInside?.()) return;
  if (isOpen) close();
  else stopAlarm();
});
document.addEventListener('pointerdown', (event) => {
  const target = event.target as Node;
  if (isOpen && !button.contains(target) && !win.contains(target)) close();
});
window.addEventListener(
  'scroll',
  () => {
    if (isOpen && openedBy !== 'scroll' && Math.abs(window.scrollY - scrollAtOpen) > scrollToClose) close();
  },
  { passive: true },
);
window.addEventListener('resize', () => {
  readSizes();
  // The room beside the notch changed: its words may fit there now, or no longer.
  if (indicators.size) showIndicators();
  reachMenubar();
  outline.set(isOpen ? openOutline() : dropState !== 'off' ? dropOutline() : closedOutline());
});

readSizes();
outline.set(closedOutline());
sizeGlow();
