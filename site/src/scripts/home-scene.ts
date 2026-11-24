// The Home chapter's scene (components/scenes/HomeScene.astro), as the app's Home and its editor work
// (Packages/Features/Home/docs/behavior.md): the utilities button puts its strip out, the pencil opens the editor, a
// widget dropped on a cell lands there and the others move aside (lib/home-layout.ts), the panel changes a size in place,
// Done keeps the layout and Cancel puts Home back. Visitors who only watch get it on a loop with a drawn pointer; any
// touch hands the scene to them. Arrow keys, or a click on a widget and then on a cell, stand in for a drag.
import { iconSvg, type IconName } from '../lib/icons';
import {
  buttonCenter,
  buttonPlace,
  cellMovedBy,
  fits,
  frame,
  freeCells,
  homeColumn,
  homeWidgets,
  initialLayout,
  moving,
  nudged,
  nudgedButton,
  placeFor,
  removed,
  resized,
  sizeLabel,
  type Cell,
  type HomeLayout,
  type WidgetPlace,
  type WidgetSize,
} from '../lib/home-layout';
import { hangingPath } from '../lib/shape';
import { copy } from './copy';
import { SpringGroup, springs } from './spring';

type WidgetId = 'timer.timer' | 'clipboard.history' | 'shelf.files';
/** What a click or a drag holds: a widget, or the utilities button. */
type Held = WidgetId | 'button';

interface WidgetInfo {
  id: WidgetId;
  place: WidgetPlace;
  name: string;
  featureName: string;
  icon: IconName;
}

/** The window's widths: the regular one, with the utilities strip out, and the editor's large one. */
const widths = { regular: 680, dock: 736, large: 880 };
/** Room for the window's shoulders at its sides, and some under it, in the stage. */
const margin = 10;
const stageHeight = 456;
/** The window's bottom corners. */
const cornerRadius = 30;
/** A target's side on screen, the scene's --target: 24 px, and a pixel to spare for the browser's rounding. */
const targetSide = 25;
/** Below this the scene is too narrow for the large window: the panel goes under the window. */
const wideFrom = 600;

/** The app's Home on a new Mac: Clipboard's history and the shelf's files, large, side by side; Timer in the row. */
const initial: HomeLayout = initialLayout(homeWidgets);

/** Where the demo leaves it: the two swapped, the shelf half as tall. */
const final: HomeLayout = {
  notchRow: 'timer.timer',
  placed: [
    { widget: 'clipboard.history', size: 'large', column: 2, row: 0 },
    { widget: 'shelf.files', size: 'medium', column: 0, row: 0 },
  ],
  button: null,
};

const clone = (layout: HomeLayout): HomeLayout => ({
  notchRow: layout.notchRow,
  placed: layout.placed.map((item) => ({ ...item })),
  button: layout.button && { ...layout.button },
});

const escape = (text: string) =>
  text.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char] ?? char);

/** An ease-in-out, as a hand drags. */
const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export function mountHome(scene: HTMLElement): void {
  const part = <T extends Element>(selector: string) => scene.querySelector<T>(selector);
  const screen = part<HTMLElement>('[data-hs-screen]');
  const shape = part<SVGSVGElement>('[data-hs-shape]');
  const fill = part<SVGPathElement>('[data-hs-fill]');
  const edge = part<SVGPathElement>('[data-hs-edge]');
  const win = part<HTMLElement>('[data-hs-window]');
  const home = part<HTMLElement>('[data-hs-home]');
  const timer = part<HTMLElement>('.hs-timer');
  const rowTitle = part<HTMLElement>('[data-hs-row-title]');
  const landing = part<HTMLElement>('[data-hs-landing]');
  const empty = part<HTMLElement>('[data-hs-empty]');
  const emptyText = part<HTMLElement>('[data-hs-empty-text]');
  const targets = part<HTMLElement>('[data-hs-targets]');
  const catcher = part<HTMLElement>('[data-hs-catch]');
  const utilities = part<HTMLButtonElement>('[data-hs-utilities]');
  const strip = part<HTMLElement>('[data-hs-strip]');
  const pencil = part<HTMLButtonElement>('[data-hs-pencil]');
  const panel = part<HTMLElement>('[data-hs-panel]');
  const list = part<HTMLElement>('[data-hs-list]');
  const sections = part<HTMLElement>('[data-hs-sections]');
  const searchField = part<HTMLInputElement>('[data-hs-search]');
  const clearSearch = part<HTMLButtonElement>('[data-hs-clear]');
  const featureView = part<HTMLElement>('[data-hs-feature]');
  const featureName = part<HTMLElement>('[data-hs-feature-name]');
  const card = part<HTMLElement>('[data-hs-wcard]');
  const done = part<HTMLButtonElement>('[data-hs-done]');
  const pointer = part<SVGSVGElement>('[data-hs-pointer]');
  const again = part<HTMLButtonElement>('[data-hs-again]');
  const status = part<HTMLElement>('[data-hs-status]');
  if (
    !screen || !shape || !fill || !edge || !win || !home || !timer || !rowTitle || !landing || !empty || !emptyText ||
    !targets || !catcher || !utilities || !strip || !pencil || !panel || !list || !sections || !searchField ||
    !clearSearch || !featureView || !featureName || !card || !done || !pointer || !again || !status
  )
    return;

  const h = copy.homeChapter;
  const a = h.app;
  const d = copy.demo;
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const cards = [...scene.querySelectorAll<HTMLElement>('.hs-card')];
  const cells = [...scene.querySelectorAll<HTMLElement>('[data-hs-cell]')];
  const targetCells = [...targets.querySelectorAll<HTMLElement>('[data-hs-target]')];

  const placeOf = (id: WidgetId): WidgetPlace => homeWidgets.find((widget) => widget.id === id)?.place ?? 'notchRow';
  const widgets: WidgetInfo[] = [
    { id: 'timer.timer', place: placeOf('timer.timer'), name: d.sidebar[1] ?? '', featureName: d.sidebar[1] ?? '', icon: 'timer' },
    { id: 'clipboard.history', place: placeOf('clipboard.history'), name: a.history, featureName: d.sidebar[2] ?? '', icon: 'clipboard' },
    { id: 'shelf.files', place: placeOf('shelf.files'), name: a.files, featureName: d.sidebar[3] ?? '', icon: 'tray' },
  ];
  const info = (id: string) => widgets.find((widget) => widget.id === id);
  const cardOf = (id: string) => cards.find((element) => element.dataset.hsWidget === id);
  const cellOf = (value: string | undefined): Cell => {
    const [column = 0, row = 0] = (value ?? '').split(',').map(Number);
    return { column, row };
  };
  for (const element of cells) place(element, frame(cellOf(element.dataset.hsCell).column, cellOf(element.dataset.hsCell).row, 'small'));
  for (const element of targetCells)
    place(element, frame(cellOf(element.dataset.hsTarget).column, cellOf(element.dataset.hsTarget).row, 'small'));

  // What Home is: the saved layout, and the editor's draft of it while the editor is open.
  let saved = clone(initial);
  let draft: HomeLayout | null = null;
  let stripOut = false;
  /** The panel: the features with widgets, or one feature's widget. */
  let view: 'list' | WidgetId = 'list';
  let search = '';
  /** Sizes chosen in the panel for widgets that aren't on Home: Add takes them. */
  const chosenSizes = new Map<WidgetId, WidgetSize>();
  /** A widget, or the button, held by a click: the next click on a cell, or on Home, puts it there. */
  let picked: Held | null = null;
  /** A drag under way, how far it has come, in the window's points. */
  let drag: { id: Held; dx: number; dy: number } | null = null;
  /** Home as it would be if what is held went where the pointer is now. */
  let preview: HomeLayout | null = null;
  let wide = true;
  let scale = 0.72;

  const layout = () => draft ?? saved;
  const editing = () => draft !== null;
  const shownIds = (from: HomeLayout) => new Set<string>([...from.placed.map((item) => item.widget), ...(from.notchRow ? [from.notchRow] : [])]);

  // Who has the scene: the demo, playing by itself, or the visitor, from their first touch until it leaves the screen.
  let touched = false;
  let run = 0;
  let state: 'idle' | 'playing' | 'done' = 'idle';
  let paused = false;
  let inView = false;
  let loopTimer = 0;
  let autoTimer = 0;
  let offer: 'pause' | 'again' | null = null;
  /** Only what the visitor does is read out: a pass of the demo, the one their Again plays included, stays silent. */
  const announce = (message: string) => {
    if (touched && state !== 'playing') status.textContent = message;
  };

  // The window's outline: it grows right for the strip and the editor, keeping its left edge, on the app's spring.
  const targetWidth = () => (editing() ? (wide ? widths.large : widths.regular) : stripOut ? widths.dock : widths.regular);
  let asked = widths.regular;
  /** Whose room the window's growth is: the editor's, opening, open or closing, or the strip's. */
  let editorRoom = false;
  /** Beside a wide window the editor's panel shows as far as the window has grown for the editor. The strip's room is
   *  the strip's own: the panel, painted over the window, stays behind its edge while the strip is out or going in. */
  const clipPanel = (width: number) => {
    if (editing()) editorRoom = true;
    else if (stripOut) editorRoom = false;
    const reach = editorRoom ? width : widths.regular;
    panel.style.clipPath = wide ? `inset(0 ${Math.max(0, widths.large - reach).toFixed(2)}px 0 0 round 0 0 30px 0)` : '';
  };
  const outline = new SpringGroup<'width'>({ width: widths.regular }, ({ width }) => {
    const body = { width, height: 440, radius: cornerRadius, shoulder: 10 };
    fill.setAttribute('d', hangingPath(body, true, margin + width / 2));
    edge.setAttribute('d', hangingPath(body, false, margin + width / 2));
    win.style.clipPath = `path('${hangingPath({ ...body, shoulder: 0 }, true, width / 2)}')`;
    clipPanel(width);
  });
  const grow = (instantly = false) => {
    const target = targetWidth();
    if (target === asked && !instantly) return;
    asked = target;
    if (instantly || reduceMotion) outline.set({ width: target });
    else void outline.to({ width: target }, springs.open);
  };

  /** A target's side in the window's points: 44, or what keeps it a target's side on screen (WCAG 2.5.8). */
  let hit = 44;

  /** The utilities button's hit area, a target's side square around it, kept whole inside Home's column, where the
   *  window's outline can't cut it, at the slot by the window's edge and wherever the editor puts the button: in the
   *  bottom right it comes in from the window's round corner. */
  const fitButtonHit = () => {
    const center = buttonCenter(layout().button);
    let x = Math.min(Math.max(center.x - hit / 2, 0), homeColumn.width - hit);
    let y = Math.min(Math.max(center.y - hit / 2, 0), homeColumn.height - hit);
    const out = { x: x + hit - (homeColumn.width - cornerRadius), y: y + hit - (homeColumn.height - cornerRadius) };
    const reach = Math.hypot(out.x, out.y);
    if (out.x > 0 && out.y > 0 && reach > cornerRadius) {
      x -= (out.x * (reach - cornerRadius)) / reach;
      y -= (out.y * (reach - cornerRadius)) / reach;
    }
    utilities.style.setProperty('--hit-x', `${x - (center.x - 22)}px`);
    utilities.style.setProperty('--hit-y', `${y - (center.y - 22)}px`);
  };

  // The window at the scene's width: the large one fits beside its panel, or the regular one over it.
  let measured = 0;
  const resize = () => {
    const available = screen.clientWidth;
    if (!available || available === measured) return;
    measured = available;
    wide = available >= wideFrom;
    const room = margin * 2 + (wide ? widths.large : widths.dock);
    scale = available / room;
    scene.style.setProperty('--s', String(scale));
    scene.classList.toggle('is-wide', wide);
    // The strip's targets keep a target's side apart, the first one whole under the window's top edge. Once they would
    // reach into Home's column, where the utilities button's hit area is, they run down from under it instead, two pixels
    // clear of it.
    hit = Math.max(44, targetSide / scale);
    const crowded = !wide && hit > 56;
    scene.classList.toggle('is-crowded', crowded);
    scene.style.setProperty('--strip-top', `${crowded ? 1.5 * hit - 22 + 2 / scale : Math.max(4, hit / 2 - 22)}px`);
    scene.style.setProperty('--strip-gap', `${Math.max(0, hit - 44)}px`);
    shape.setAttribute('viewBox', `0 0 ${room} ${stageHeight}`);
    fitButtonHit();
    grow(true);
  };
  new ResizeObserver(resize).observe(screen);

  /** In the editor a widget is its handle, a button over its card for the keyboard and screen readers, beside its "−";
   *  outside the editor it has none. */
  const editable = (element: HTMLElement, id: WidgetId, on: boolean) => {
    const handle = element.querySelector<HTMLButtonElement>('[data-hs-handle]');
    const widget = info(id);
    if (!handle) return;
    handle.hidden = !on || !widget;
    if (!on || !widget) return;
    // The notch row's widget is its feature's own name once, and the arrow keys don't move it.
    handle.setAttribute('aria-label', widget.name === widget.featureName ? widget.name : `${widget.featureName}, ${widget.name}`);
    handle.setAttribute('aria-describedby', id === 'timer.timer' ? 'hs-row-keys' : 'hs-widget-keys');
    handle.setAttribute('aria-pressed', String(picked === id));
  };

  const render = () => {
    const isEditing = editing();
    const current = layout();
    const shown = preview ?? current;
    scene.classList.toggle('is-editing', isEditing);
    scene.classList.toggle('has-strip', stripOut && !isEditing);
    scene.classList.toggle('is-picking-widget', isEditing && picked !== null && picked !== 'button');
    scene.classList.toggle('is-picking-button', isEditing && picked === 'button');
    strip.inert = !(stripOut && !isEditing);
    panel.inert = !isEditing;
    grow();
    clipPanel(outline.values.width);

    // The notch row: its widget, or Home's title.
    const rowWidget = shown.notchRow === 'timer.timer';
    timer.hidden = !rowWidget;
    rowTitle.hidden = rowWidget;
    timer.classList.toggle('is-picked', picked === 'timer.timer');
    editable(timer, 'timer.timer', isEditing && rowWidget);

    // The cards where the layout puts them; the dragged one follows the pointer from its own place, and a picked one stays
    // there too, under the outline of where it would land, so the cell under the pointer keeps the click.
    for (const element of cards) {
      const id = element.dataset.hsWidget as WidgetId;
      const own = current.placed.find((item) => item.widget === id);
      const held = drag?.id === id || picked === id;
      const placement = held ? own : (shown.placed.find((item) => item.widget === id) ?? own);
      element.hidden = !placement;
      editable(element, id, isEditing && !!placement);
      if (!placement) continue;
      const box = frame(placement.column, placement.row, placement.size);
      const isDragged = drag?.id === id;
      element.style.transform = `translate(${box.x + (isDragged ? drag!.dx : 0)}px, ${box.y + (isDragged ? drag!.dy : 0)}px)`;
      element.style.width = `${box.width}px`;
      element.style.height = `${box.height}px`;
      element.dataset.size = placement.size;
      element.classList.toggle('is-dragged', isDragged);
      element.classList.toggle('is-picked', picked === id);
    }

    // In the editor the free cells show dashed, and the place a held widget would land is outlined.
    const free = isEditing ? freeCells(shown.placed) : [];
    for (const element of cells) {
      const cell = cellOf(element.dataset.hsCell);
      element.classList.toggle('is-free', free.some((item) => item.column === cell.column && item.row === cell.row));
    }
    const held = drag ? drag.id : picked;
    const lands = held && held !== 'button' && preview ? preview.placed.find((item) => item.widget === held) : undefined;
    landing.classList.toggle('is-shown', !!lands);
    if (lands) place(landing, frame(lands.column, lands.row, lands.size));
    empty.hidden = isEditing || shown.placed.length > 0;
    emptyText.textContent = shown.notchRow ? a.emptyGrid : a.empty;

    // The utilities button, in its slot or where the editor put it.
    const center = buttonCenter(current.button);
    const isDragged = drag?.id === 'button';
    utilities.style.transform = `translate(${center.x - 22 + (isDragged ? drag!.dx : 0)}px, ${center.y - 22 + (isDragged ? drag!.dy : 0)}px)`;
    fitButtonHit();
    utilities.classList.toggle('is-floating', current.button !== null || isDragged);
    utilities.classList.toggle('is-dragged', isDragged);
    utilities.classList.toggle('is-picked', picked === 'button');
    if (isEditing) {
      utilities.removeAttribute('aria-expanded');
      utilities.setAttribute('aria-pressed', String(picked === 'button'));
      utilities.setAttribute('aria-describedby', 'hs-button-keys');
    } else {
      utilities.setAttribute('aria-expanded', String(stripOut));
      utilities.removeAttribute('aria-pressed');
      utilities.removeAttribute('aria-describedby');
    }
    renderPanel();
  };

  // The panel: Cancel and Done, then the features with widgets, or one feature's widget with its sizes.
  const subtitle = (widget: WidgetInfo) => {
    const current = layout();
    if (widget.place === 'notchRow' && current.notchRow === widget.id) return a.inNotchRow;
    return shownIds(current).has(widget.id) ? `${a.widgets(1)} · ${a.onHomeOne}` : a.widgets(1);
  };

  const renderSections = () => {
    const query = search.trim().toLocaleLowerCase();
    const shown = shownIds(layout());
    const matches = (widget: WidgetInfo) =>
      !query || widget.featureName.toLocaleLowerCase().includes(query) || widget.name.toLocaleLowerCase().includes(query);
    const row = (widget: WidgetInfo) =>
      `<button class="hs-frow" type="button" data-hs-open="${widget.id}" data-key="open-${widget.id}"><span class="hs-frow__icon">${iconSvg(widget.icon, 15)}</span><span class="hs-frow__text"><span class="hs-frow__name">${escape(widget.featureName)}</span><span class="hs-frow__sub">${escape(subtitle(widget))}</span></span><span class="hs-frow__chevron" aria-hidden="true">›</span></button>`;
    const onHome = widgets.filter((widget) => matches(widget) && shown.has(widget.id));
    const more = widgets.filter((widget) => matches(widget) && !shown.has(widget.id));
    sections.innerHTML =
      (onHome.length ? `<p class="hs-section">${escape(a.onHome)}</p>${onHome.map(row).join('')}` : '') +
      (more.length ? `<p class="hs-section">${escape(a.more)}</p>${more.map(row).join('')}` : '') +
      (!onHome.length && !more.length ? `<p class="hs-none">${escape(a.nothingFound)}</p>` : '');
  };

  /** The widget at its real size, scaled down into the panel's 154 × 96, or a narrow scene's smaller box beside its sizes. */
  const thumbnail = (widget: WidgetInfo, size: WidgetSize | undefined) => {
    const real = size ? frame(0, 0, size) : { width: homeColumn.width, height: homeColumn.row };
    const room = wide ? { width: 154, height: 96 } : { width: 104, height: 64 };
    const k = Math.min(room.width / real.width, room.height / real.height);
    const box = document.createElement('div');
    box.className = 'hs-thumb';
    box.style.setProperty('--k', String(k));
    box.style.width = `${real.width * k}px`;
    box.style.height = `${real.height * k}px`;
    const source = widget.id === 'timer.timer' ? timer : cardOf(widget.id)?.querySelector('[data-hs-face]');
    const face = (source?.cloneNode(true) as HTMLElement | undefined) ?? document.createElement('div');
    face.querySelectorAll('.hs-ring, .hs-remove, .hs-handle').forEach((element) => element.remove());
    face.removeAttribute('tabindex');
    for (const name of ['role', 'aria-label', 'aria-describedby', 'aria-pressed', 'hidden', 'data-hs-widget']) face.removeAttribute(name);
    face.classList.remove('is-picked', 'is-hover');
    face.setAttribute('aria-hidden', 'true');
    face.style.width = `${real.width}px`;
    face.style.height = `${real.height}px`;
    if (size) face.dataset.size = size;
    box.append(face);
    return box;
  };

  const renderFeature = (id: WidgetId) => {
    const widget = info(id);
    if (!widget) return;
    featureName.textContent = widget.featureName;
    const current = layout();
    const placement = current.placed.find((item) => item.widget === id);
    const onHome = shownIds(current).has(id);
    const sizes = widget.place === 'notchRow' ? [] : widget.place;
    const size = placement?.size ?? chosenSizes.get(id) ?? sizes[0];
    const room = onHome || placeFor(current, id, widget.place, size) !== null;
    const action = onHome
      ? `<span class="hs-quiet">${escape(a.onHome)}</span>`
      : room
        ? `<button class="hs-add" type="button" data-hs-add="${id}" data-key="add">${escape(a.add)}</button>`
        : `<span class="hs-quiet">${escape(a.noRoom)}</span>`;
    const chips = sizes
      .map((option) => {
        const isChosen = option === size;
        // On Home a size applies in place, so one that doesn't fit there is dimmed; the chosen one stays as it is.
        const usable = isChosen || !placement || fits(current.placed, option, placement.column, placement.row, id);
        return `<button class="hs-chip${isChosen ? ' is-chosen' : ''}" type="button" data-hs-size="${option}" data-key="size-${option}" aria-pressed="${isChosen}"${usable ? '' : ' disabled'}>${sizeLabel(option)}</button>`;
      })
      .join('');
    card.innerHTML =
      `<div class="hs-wcard__row"><span>${escape(widget.name)}</span>${action}</div>` +
      (sizes.length ? `<div class="hs-chips">${chips}</div>` : `<p class="hs-quiet">${escape(a.inNotchRow)}</p>`) +
      (!room && sizes.length ? `<p class="hs-hint">${escape(a.noRoomHint)}</p>` : '');
    card.prepend(thumbnail(widget, size));
  };

  const renderPanel = () => {
    // Redrawn lists keep the focus where it was.
    const focused = panel.contains(document.activeElement) ? (document.activeElement as HTMLElement).dataset.key : undefined;
    list.hidden = view !== 'list';
    featureView.hidden = view === 'list';
    clearSearch.hidden = search === '';
    if (view === 'list') renderSections();
    else renderFeature(view);
    if (focused) panel.querySelector<HTMLElement>(`[data-key="${focused}"]`)?.focus({ preventScroll: true });
  };

  // What the editor does.
  const commit = (next: HomeLayout) => {
    if (draft) draft = next;
  };

  const openEditor = (fromKeyboard = false) => {
    draft = clone(saved);
    stripOut = false;
    view = 'list';
    search = '';
    searchField.value = '';
    chosenSizes.clear();
    picked = null;
    preview = null;
    drag = null;
    const lost = strip.contains(document.activeElement) || document.activeElement === document.body;
    render();
    // A keyboard goes on from the first widget, where the arrow keys move it; a click keeps the focus in the scene,
    // where Esc reaches the editor. The demo playing by itself moves no focus.
    if (fromKeyboard) (scene.querySelector<HTMLElement>('.hs-handle:not([hidden])') ?? done).focus({ preventScroll: true });
    else if (touched && lost) scene.focus({ preventScroll: true });
  };

  const endEditor = (keep: boolean) => {
    if (!draft) return;
    const hadFocus = home.contains(document.activeElement) || panel.contains(document.activeElement);
    if (keep) saved = clone(draft);
    draft = null;
    picked = null;
    preview = null;
    drag = null;
    view = 'list';
    search = '';
    searchField.value = '';
    chosenSizes.clear();
    announce(keep ? h.kept : h.putBack);
    render();
    if (hadFocus) utilities.focus({ preventScroll: true });
  };

  const removeWidget = (id: WidgetId, fromKeyboard = false) => {
    if (!draft) return;
    const order = [...scene.querySelectorAll<HTMLElement>('.hs-handle:not([hidden])')];
    const next = order[order.findIndex((element) => element.closest<HTMLElement>('.hs-widget')?.dataset.hsWidget === id) + 1];
    draft = removed(draft, id);
    if (picked === id) picked = null;
    announce(h.removed(info(id)?.featureName ?? ''));
    render();
    if (fromKeyboard) (next && !next.hidden ? next : done).focus({ preventScroll: true });
  };

  const applySize = (id: WidgetId, size: WidgetSize) => {
    const current = layout();
    if (current.placed.some((item) => item.widget === id)) {
      const next = resized(current, id, size);
      if (!next) return;
      commit(next);
      announce(h.resized(info(id)?.featureName ?? '', sizeLabel(size)));
    } else {
      chosenSizes.set(id, size);
    }
    render();
  };

  const addWidget = (id: WidgetId) => {
    const widget = info(id);
    const next = widget && placeFor(layout(), id, widget.place, chosenSizes.get(id));
    if (!widget || !next) return;
    const hadFocus = card.contains(document.activeElement);
    commit(next);
    announce(h.added(widget.featureName));
    render();
    // Add goes once the widget is on Home: the focus moves on to its sizes, or back to the list.
    if (hadFocus) (card.querySelector<HTMLElement>('.hs-chip.is-chosen') ?? part<HTMLElement>('[data-hs-back]'))?.focus({ preventScroll: true });
  };

  const pick = (held: Held | null) => {
    picked = held;
    preview = null;
    render();
  };

  /** Where Home would be if the drag let go now: the dragged widget on the cell nearest its corner. */
  const dragPreview = (): HomeLayout | null => {
    if (!drag || drag.id === 'button') return null;
    const id = drag.id;
    const own = layout().placed.find((item) => item.widget === id);
    if (!own) return null;
    const cell = cellMovedBy(own, drag.dx, drag.dy);
    return moving(layout(), id, cell.column, cell.row);
  };

  /** The drag lets go: the widget lands where the grid showed it, the others moved aside, or goes back; the button
   *  settles where the rules put it. */
  const drop = (cancelled = false) => {
    if (!drag) return;
    const { id, dx, dy } = drag;
    if (!cancelled && id === 'button') {
      const center = buttonCenter(layout().button);
      commit({ ...layout(), button: buttonPlace({ x: center.x + dx, y: center.y + dy }) });
      announce(h.moved(d.utilities));
    } else if (!cancelled && preview) {
      commit(preview);
      announce(h.moved(info(id)?.featureName ?? ''));
    }
    drag = null;
    preview = null;
    render();
  };

  /** A point on the page, in the points of Home's column. */
  const inColumn = (clientX: number, clientY: number) => {
    const box = home.getBoundingClientRect();
    return { x: (clientX - box.left) / scale, y: (clientY - box.top) / scale };
  };

  // The pointer: a press that moves drags, one that doesn't picks (a click).
  let press: { id: Held; x: number; y: number; pointerId: number; moved: boolean } | null = null;
  let skipClick = false;
  const startPress = (event: PointerEvent, id: Held, element: HTMLElement) => {
    if (!editing() || event.button !== 0 || !event.isPrimary) return;
    press = { id, x: event.clientX, y: event.clientY, pointerId: event.pointerId, moved: false };
    element.setPointerCapture(event.pointerId);
  };
  for (const element of cards)
    element.addEventListener('pointerdown', (event) => {
      if ((event.target as Element).closest('.hs-remove')) return;
      startPress(event, element.dataset.hsWidget as WidgetId, element);
    });
  utilities.addEventListener('pointerdown', (event) => startPress(event, 'button', utilities));
  scene.addEventListener('pointermove', (event) => {
    if (!press || event.pointerId !== press.pointerId) return;
    if (!press.moved && Math.hypot(event.clientX - press.x, event.clientY - press.y) < 3) return;
    press.moved = true;
    picked = null;
    drag = { id: press.id, dx: (event.clientX - press.x) / scale, dy: (event.clientY - press.y) / scale };
    preview = dragPreview();
    render();
  });
  const endPress = (event: PointerEvent, cancelled: boolean) => {
    if (!press || event.pointerId !== press.pointerId) return;
    const { id, moved } = press;
    press = null;
    if (moved) {
      if (id === 'button') skipClick = true;
      drop(cancelled);
    } else if (!cancelled && id !== 'button') {
      pick(picked === id ? null : id);
    }
  };
  scene.addEventListener('pointerup', (event) => endPress(event, false));
  scene.addEventListener('pointercancel', (event) => endPress(event, true));

  // With a widget picked, each cell shows where it would go, and a click puts it there.
  targets.addEventListener('pointerover', (event) => {
    const target = (event.target as Element).closest<HTMLElement>('[data-hs-target]');
    if (!target || !picked || picked === 'button') return;
    const cell = cellOf(target.dataset.hsTarget);
    for (const element of targetCells) element.classList.toggle('is-hover', element === target);
    preview = moving(layout(), picked, cell.column, cell.row);
    render();
  });
  targets.addEventListener('pointerleave', () => {
    for (const element of targetCells) element.classList.remove('is-hover');
    preview = null;
    render();
  });
  targets.addEventListener('click', (event) => {
    const target = (event.target as Element).closest<HTMLElement>('[data-hs-target]');
    if (!target || !picked || picked === 'button') return;
    const id = picked;
    const cell = cellOf(target.dataset.hsTarget);
    const next = moving(layout(), id, cell.column, cell.row);
    const own = layout().placed.find((item) => item.widget === id);
    if (next) {
      commit(next);
      announce(h.moved(info(id)?.featureName ?? ''));
    } else if (!own || own.column !== cell.column || own.row !== cell.row) {
      return;
    }
    for (const element of targetCells) element.classList.remove('is-hover');
    pick(null);
  });

  // A click on Home with the strip out only puts it away; with the button picked it puts the button there.
  catcher.addEventListener('click', (event) => {
    if (editing() && picked === 'button') {
      const point = inColumn(event.clientX, event.clientY);
      commit({ ...layout(), button: buttonPlace(point) });
      announce(h.moved(d.utilities));
      pick(null);
      return;
    }
    stripOut = false;
    render();
  });

  utilities.addEventListener('click', () => {
    if (skipClick) {
      skipClick = false;
      return;
    }
    if (editing()) pick(picked === 'button' ? null : 'button');
    else {
      stripOut = !stripOut;
      render();
    }
  });
  // A click's detail is 0 when the keyboard pressed it.
  pencil.addEventListener('click', (event) => openEditor(event.detail === 0));
  part<HTMLButtonElement>('[data-hs-edit]')?.addEventListener('click', (event) => openEditor(event.detail === 0));
  strip.addEventListener('click', (event) => {
    if (!(event.target as Element).closest('a')) return;
    stripOut = false;
    render();
  });
  for (const button of scene.querySelectorAll<HTMLButtonElement>('[data-hs-remove]'))
    button.addEventListener('click', () => removeWidget(button.dataset.hsRemove as WidgetId));

  panel.addEventListener('click', (event) => {
    const target = (event.target as Element).closest<HTMLButtonElement>('button');
    if (!target) return;
    const hadFocus = document.activeElement === target;
    if (target.matches('[data-hs-cancel]')) endEditor(false);
    else if (target.matches('[data-hs-done], [data-hs-more]')) endEditor(true);
    else if (target.dataset.hsOpen) {
      view = target.dataset.hsOpen as WidgetId;
      renderPanel();
      if (hadFocus) part<HTMLElement>('[data-hs-back]')?.focus({ preventScroll: true });
    } else if (target.matches('[data-hs-back]')) {
      const from = view;
      view = 'list';
      renderPanel();
      if (hadFocus) sections.querySelector<HTMLElement>(`[data-hs-open="${from}"]`)?.focus({ preventScroll: true });
    } else if (target.dataset.hsSize && view !== 'list') applySize(view, target.dataset.hsSize as WidgetSize);
    else if (target.dataset.hsAdd) addWidget(target.dataset.hsAdd as WidgetId);
    else if (target.matches('[data-hs-clear]')) {
      search = '';
      searchField.value = '';
      renderPanel();
      searchField.focus();
    }
  });
  searchField.addEventListener('input', () => {
    search = searchField.value;
    renderPanel();
  });

  const arrows: Record<string, [number, number]> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
  scene.addEventListener('keydown', (event) => {
    const target = event.target as HTMLElement;
    if (event.key === 'Escape') {
      // Esc empties the search first, then lets go of what is held, then leaves the editor as Cancel does.
      if (target === searchField && search) {
        search = '';
        searchField.value = '';
        renderPanel();
      } else if (drag) {
        press = null;
        drop(true);
      } else if (picked) {
        pick(null);
      } else if (editing()) {
        endEditor(false);
      } else if (stripOut) {
        const inStrip = strip.contains(document.activeElement);
        stripOut = false;
        render();
        if (inStrip) utilities.focus({ preventScroll: true });
      }
      return;
    }
    if (!editing()) return;
    const step = arrows[event.key];
    if (target === utilities && step) {
      event.preventDefault();
      const next = nudgedButton(layout().button, step[0], step[1]);
      if (JSON.stringify(next) === JSON.stringify(layout().button)) return;
      commit({ ...layout(), button: next });
      announce(h.moved(d.utilities));
      render();
      return;
    }
    const widget = target.matches('[data-hs-handle]') ? target.closest<HTMLElement>('.hs-widget') : null;
    if (!widget) return;
    const id = widget.dataset.hsWidget as WidgetId;
    if (step) {
      event.preventDefault();
      const next = id === 'timer.timer' ? null : nudged(layout(), id, step[0], step[1]);
      if (!next) return;
      commit(next);
      picked = null;
      announce(h.moved(info(id)?.featureName ?? ''));
      render();
    } else if (event.key === 'Delete' || event.key === 'Backspace') {
      event.preventDefault();
      removeWidget(id, true);
    }
  });
  // Enter or Space on a widget's handle picks it, as a click does; a click of the pointer picks it on its own way up.
  for (const handle of scene.querySelectorAll<HTMLButtonElement>('[data-hs-handle]'))
    handle.addEventListener('click', (event) => {
      if (event.detail !== 0) return;
      const id = handle.closest<HTMLElement>('.hs-widget')?.dataset.hsWidget as WidgetId | undefined;
      if (id) pick(picked === id ? null : id);
    });

  // The demo: it plays by itself while it is in view, with a drawn pointer, until the visitor touches it.
  const looping = () => !touched && !paused && !reduceMotion;
  /** A step's pause; with Reduce Motion a short beat, so a pass still shows each step, one after another, unmoving. */
  const wait = (ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, reduceMotion ? Math.min(ms, 280) : ms));

  const movePointer = (x: number, y: number) => {
    pointer.style.setProperty('--px', `${x.toFixed(1)}px`);
    pointer.style.setProperty('--py', `${y.toFixed(1)}px`);
  };
  /** Where the pointer would touch `element`, `ox` and `oy` across it, from the screen's top left. */
  const spot = (element: Element, ox = 0.5, oy = 0.5) => {
    const box = element.getBoundingClientRect();
    const base = screen.getBoundingClientRect();
    return { x: box.left - base.left + box.width * ox, y: box.top - base.top + box.height * oy };
  };
  const pointAt = async (element: Element | null, ox = 0.5, oy = 0.5) => {
    if (!element) return;
    const to = spot(element, ox, oy);
    movePointer(to.x, to.y);
    await wait(620);
  };
  /** The pointer presses `element`: it lights, then the press shows. */
  const tap = async (element: Element | null, current: number) => {
    if (!element) return false;
    element.classList.add('is-hover');
    await wait(200);
    element.classList.add('is-pressed');
    await wait(150);
    element.classList.remove('is-pressed', 'is-hover');
    return current === run;
  };
  /** Calls `step` with the eased progress every frame for `ms`; stops once another run takes over. */
  const tween = (ms: number, step: (t: number) => void, current: number) =>
    new Promise<void>((resolve) => {
      if (reduceMotion) {
        step(1);
        resolve();
        return;
      }
      const start = performance.now();
      const frameStep = (now: number) => {
        if (current !== run) return resolve();
        const progress = Math.min(1, (now - start) / ms);
        step(ease(progress));
        if (progress < 1) requestAnimationFrame(frameStep);
        else resolve();
      };
      requestAnimationFrame(frameStep);
    });

  const offerSlot = (next: typeof offer) => {
    offer = next;
    again.textContent = next === 'pause' ? copy.chapter.pause : h.replay;
    again.classList.toggle('is-shown', next !== null);
  };
  /** The slot under the scene: Pause while a pass plays, or while the loop waits to go round again; Again once it rests.
   *  It never changes under the visitor's focus: only pressing it does, and the end of the pass it paused. */
  const sync = () => {
    if (document.activeElement === again) return;
    if (state === 'playing' || (looping() && (state === 'done' || autoTimer !== 0))) offerSlot('pause');
    else offerSlot(state === 'done' ? 'again' : null);
  };

  /** Home as a new Mac has it, the editor closed. */
  const reset = (to: HomeLayout) => {
    saved = clone(to);
    draft = null;
    stripOut = false;
    view = 'list';
    search = '';
    searchField.value = '';
    chosenSizes.clear();
    picked = null;
    preview = null;
    drag = null;
    press = null;
    render();
    grow(true);
  };

  /** What a pass leaves half done when the visitor takes over: the pointer goes, and a drag lands where it shows. */
  const settle = () => {
    pointer.classList.remove('is-shown', 'is-tracking');
    scene.querySelectorAll('.is-hover, .is-pressed').forEach((element) => element.classList.remove('is-hover', 'is-pressed'));
    scene.classList.remove('is-resetting');
    if (drag && !press) drop();
  };

  /** One pass: by itself only for a visitor who watches, never once they have the scene; `forVisitor`, their Again. */
  const play = async (forVisitor = false) => {
    if (!forVisitor && (touched || paused)) return;
    const current = ++run;
    state = 'playing';
    window.clearTimeout(loopTimer);
    loopTimer = 0;
    reset(initial);
    sync();
    const alive = () => current === run;
    pointer.classList.add('is-tracking');
    const rest = spot(home, 0.42, 0.62);
    movePointer(rest.x, rest.y);
    pointer.getBoundingClientRect();
    pointer.classList.remove('is-tracking');
    pointer.classList.add('is-shown');
    await wait(700);
    // The utilities button puts its strip out.
    await pointAt(utilities);
    if (!alive() || !(await tap(utilities, current))) return;
    stripOut = true;
    render();
    await wait(650);
    if (!alive()) return;
    // The pencil, the strip's last button, opens the editor.
    await pointAt(pencil);
    if (!alive() || !(await tap(pencil, current))) return;
    openEditor();
    await wait(850);
    if (!alive()) return;
    // The clipboard dragged onto the shelf: they trade places.
    const clipboard = cardOf('clipboard.history');
    await pointAt(clipboard ?? null, 0.4, 0.3);
    if (!alive() || !clipboard) return;
    clipboard.classList.add('is-hover');
    await wait(350);
    clipboard.classList.remove('is-hover');
    const from = spot(clipboard, 0.4, 0.3);
    const span = frame(2, 0, 'small').x - frame(0, 0, 'small').x;
    pointer.classList.add('is-tracking');
    await tween(
      1100,
      (t) => {
        drag = { id: 'clipboard.history', dx: span * t, dy: 10 * Math.sin(Math.PI * t) };
        preview = dragPreview();
        render();
        movePointer(from.x + drag.dx * scale, from.y + drag.dy * scale);
      },
      current,
    );
    pointer.classList.remove('is-tracking');
    if (!alive()) return;
    drop();
    await wait(750);
    if (!alive()) return;
    // The shelf in the panel: its widget's sizes; the smaller one makes it half as tall.
    const shelfRow = sections.querySelector('[data-hs-open="shelf.files"]');
    await pointAt(shelfRow, 0.35, 0.5);
    if (!alive() || !(await tap(shelfRow, current))) return;
    view = 'shelf.files';
    renderPanel();
    await wait(800);
    if (!alive()) return;
    const medium = card.querySelector('[data-hs-size="medium"]');
    await pointAt(medium);
    if (!alive() || !(await tap(medium, current))) return;
    applySize('shelf.files', 'medium');
    await wait(1000);
    if (!alive()) return;
    // Done keeps it.
    await pointAt(done);
    if (!alive() || !(await tap(done, current))) return;
    endEditor(true);
    finish(current);
  };

  /** The pass ends on Home as it was left; for a visitor who only watches, it all starts over a moment later. */
  const finish = (current: number) => {
    if (current !== run) return;
    state = 'done';
    pointer.classList.remove('is-shown');
    // The visitor's own pass is over: its Pause becomes Again, even under their focus.
    if (offer === 'pause' && !looping()) offerSlot('again');
    else sync();
    if (looping() && inView)
      loopTimer = window.setTimeout(async () => {
        loopTimer = 0;
        scene.classList.add('is-resetting');
        await wait(320);
        scene.classList.remove('is-resetting');
        if (looping() && inView && state === 'done') void play();
      }, 3600);
  };

  /** Where a paused demo rests: the end of a pass, drawn at once, with nothing moving. */
  const still = () => {
    run++;
    state = 'done';
    window.clearTimeout(loopTimer);
    loopTimer = 0;
    pointer.classList.remove('is-shown', 'is-tracking');
    scene.classList.remove('is-resetting');
    reset(final);
  };

  // Any touch hands the scene to the visitor: no more rounds on their own, and what the pass left half done settles.
  const takeOver = (event: Event) => {
    if (event.target instanceof Node && again.contains(event.target)) return;
    window.clearTimeout(loopTimer);
    loopTimer = 0;
    window.clearTimeout(autoTimer);
    autoTimer = 0;
    // Settled before the visitor has it, so what the demo did is not read out as theirs.
    if (state === 'playing') {
      run++;
      state = 'done';
      settle();
    }
    touched = true;
    sync();
  };
  scene.addEventListener('pointerdown', takeOver, { capture: true });
  scene.addEventListener('keydown', takeOver, { capture: true });
  scene.addEventListener('focusin', takeOver);
  again.addEventListener('blur', sync);

  // Pause stops the demo at once and rests it on a still frame; Again then plays one pass for the visitor.
  again.addEventListener('click', () => {
    if (offer === 'pause') {
      paused = true;
      window.clearTimeout(autoTimer);
      autoTimer = 0;
      still();
      offerSlot('again');
      return;
    }
    // Again: one pass for the visitor who asked for it, and Pause stops it.
    touched = true;
    offerSlot('pause');
    void play(true);
  });

  // It starts when it comes into view and goes round while it stays there. Off screen it rests, and the visitor's turn
  // ends unless their focus is still in it.
  new IntersectionObserver(
    ([entry]) => {
      inView = entry?.isIntersecting ?? false;
      window.clearTimeout(autoTimer);
      autoTimer = 0;
      if (!inView) {
        if (!scene.contains(document.activeElement)) touched = false;
        window.clearTimeout(loopTimer);
        loopTimer = 0;
        sync();
        return;
      }
      // A moment after it is well in view, for a visitor who only watches: never once they have it, or have paused it.
      const ready = () => !touched && !paused && (state === 'idle' || (state === 'done' && !loopTimer));
      if ((entry?.intersectionRatio ?? 0) >= 0.6 && ready())
        autoTimer = window.setTimeout(() => {
          autoTimer = 0;
          if (inView && ready()) void play();
          else sync();
        }, 1000);
      sync();
    },
    { threshold: [0, 0.6] },
  ).observe(scene);

  resize();
  render();
}

/** Puts an element at a box in the window's points. */
function place(element: HTMLElement, box: { x: number; y: number; width: number; height: number }): void {
  element.style.transform = `translate(${box.x}px, ${box.y}px)`;
  element.style.width = `${box.width}px`;
  element.style.height = `${box.height}px`;
}
