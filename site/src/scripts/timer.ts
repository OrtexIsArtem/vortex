// The visitor's own timer, one at a time as in the app. While it runs, the notch's left ear and the tab's title count
// down; when time is up the notch flashes until the pointer comes over it, and a notification offers five more
// minutes. It lasts as long as the page.
import { appLang, copy } from './copy';
import {
  clockText,
  fractionLeft,
  isOver,
  isPaused,
  pause,
  resume,
  secondsLeft,
  startRun,
  untilNextSecond,
  type Run,
} from '../lib/timer-run';
import { alarm, setIndicator, stopAlarm } from './notch';

export interface TimerState {
  run: Run | null;
  /** Seconds, on the clock the run uses. */
  now: number;
}

type Listener = (state: TimerState) => void;

const listeners = new Set<Listener>();
const baseTitle = document.title;
const toast = document.querySelector<HTMLElement>('[data-toast]');
/** Read out by screen readers: once a minute while a run goes, and when time is up. */
const status = document.querySelector<HTMLElement>('[data-timer-status]');
let run: Run | null = null;
let timesUp = false;
let wake = 0;
let toastTimer = 0;

const now = () => Date.now() / 1000;

/** Reads `text` out, in `lang` when it is the app's own words rather than the page's. */
function say(text: string, lang?: string): void {
  if (!status) return;
  if (lang) status.lang = lang;
  else status.removeAttribute('lang');
  status.textContent = text;
}

/** Calls `listener` now and on every change and second; returns a function that stops it. */
export function onTimer(listener: Listener): () => void {
  listeners.add(listener);
  listener({ run, now: now() });
  return () => listeners.delete(listener);
}

function emit(): void {
  const t = now();
  if (run) {
    const clock = clockText(secondsLeft(run, t));
    setIndicator('timer', {
      left: [isPaused(run) ? { kind: 'icon', name: 'pause' } : { kind: 'ring', value: fractionLeft(run, t) }, { kind: 'text', text: clock }],
      priority: 10,
    });
    document.title = copy.timer.title(clock, isPaused(run));
    const seconds = secondsLeft(run, t);
    if (status && !isPaused(run) && seconds > 0 && seconds % 60 === 0) say(copy.timer.left(seconds / 60));
  } else {
    setIndicator('timer', null);
    document.title = timesUp ? copy.timer.titleUp : baseTitle;
  }
  for (const listener of listeners) listener({ run, now: t });
}

/** Wakes exactly as the shown time changes, at each whole second. */
function schedule(): void {
  window.clearTimeout(wake);
  if (!run || isPaused(run)) return;
  const t = now();
  if (isOver(run, t)) {
    finish();
    return;
  }
  wake = window.setTimeout(() => {
    emit();
    schedule();
  }, untilNextSecond(run, t) * 1000 + 5);
}

export function start(minutes: number): void {
  run = startRun(minutes, now());
  timesUp = false;
  stopAlarm();
  hideToast();
  emit();
  schedule();
}

export function togglePause(): void {
  if (!run) return;
  run = isPaused(run) ? resume(run, now()) : pause(run, now());
  emit();
  schedule();
}

/** Ends the run without the alarm. */
export function stop(): void {
  run = null;
  window.clearTimeout(wake);
  emit();
}

function finish(): void {
  run = null;
  timesUp = true;
  emit();
  say(copy.timer.timesUp, appLang);
  alarm('alarm');
  showToast();
}

function showToast(): void {
  if (!toast) return;
  window.clearTimeout(toastTimer);
  toast.hidden = false;
  requestAnimationFrame(() => toast.classList.add('is-shown'));
}

function hideToast(): void {
  if (!toast || toast.hidden) return;
  window.clearTimeout(toastTimer);
  toast.classList.remove('is-shown');
  toastTimer = window.setTimeout(() => (toast.hidden = true), 400);
}

// Once the visitor has seen the alarm the title comes back, and the notification leaves a little later.
document.addEventListener('vx:alarm-seen', () => {
  if (!timesUp) return;
  timesUp = false;
  emit();
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(hideToast, 6000);
});

toast?.querySelector('[data-toast-more]')?.addEventListener('click', () => start(5));
toast?.querySelector('[data-toast-close]')?.addEventListener('click', () => {
  stopAlarm();
  hideToast();
});

/** Only for trying the alarm without waiting: time's up in `seconds`. */
export function startSeconds(seconds: number): void {
  const t = now();
  run = { phase: { kind: 'running', endsAt: t + seconds }, total: seconds };
  timesUp = false;
  hideToast();
  emit();
  schedule();
}
