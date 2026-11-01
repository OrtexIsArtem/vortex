// Line icons in one style: 24 × 24, 1.6 stroke, round ends. Drawn for this site after the app's own symbols.

function gear(): string {
  const step = (Math.PI * 2) / 8;
  const at = (radius: number, angle: number) =>
    `${(12 + radius * Math.cos(angle)).toFixed(2)} ${(12 + radius * Math.sin(angle)).toFixed(2)}`;
  const points: string[] = [];
  for (let tooth = 0; tooth < 8; tooth++) {
    const a = tooth * step - Math.PI / 2;
    points.push(at(8.6, a - step * 0.17), at(8.6, a + step * 0.17), at(6.6, a + step * 0.33), at(6.6, a + step * 0.67));
  }
  return `<path d="M${points.join('L')}Z"/><circle cx="12" cy="12" r="2.8"/>`;
}

export const icons = {
  grid: '<rect x="4" y="4" width="6.5" height="6.5" rx="1.8"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.8"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.8"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.8"/>',
  timer: '<circle cx="12" cy="13.5" r="7.2"/><path d="M12 13.5V9.6M9.8 3.2h4.4M18.6 6.6l1.3-1.3"/>',
  clipboard: '<rect x="5.5" y="5" width="13" height="16" rx="2.6"/><path d="M9 5v-.4A1.6 1.6 0 0 1 10.6 3h2.8A1.6 1.6 0 0 1 15 4.6V5M9 11h6M9 15h4"/>',
  tray: '<path d="M3.5 13.5 6 5.5h12l2.5 8V18a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 18z"/><path d="M3.5 13.5h5a3.5 3.5 0 0 0 7 0h5"/>',
  checklist: '<path d="m4 7.2 1.6 1.6 2.9-2.9M4 15.7l1.6 1.6 2.9-2.9M11.5 7.5H20M11.5 16H20"/>',
  key: '<circle cx="7" cy="12" r="3.6"/><path d="M10.6 12H21M18.2 12v3M15.2 12v2.2"/>',
  gear: gear(),
  keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.6"/><path d="M6.2 10h.01M9.4 10h.01M12.6 10h.01M15.8 10h.01M7.6 14h8.8"/>',
  play: '<path d="M8 5.2v13.6L19 12z" fill="currentColor" stroke="none"/>',
  pause: '<path d="M7.5 5.5h3v13h-3zM13.5 5.5h3v13h-3z" fill="currentColor" stroke="none"/>',
  stop: '<rect x="6.5" y="6.5" width="11" height="11" rx="2.2" fill="currentColor" stroke="none"/>',
  check: '<path d="m5.5 12.5 4 4 9-9"/>',
  eye: '<path d="M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12s-3.5 6.5-9.5 6.5S2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/>',
  pin: '<path d="M9 3.5h6M10 3.5v6l-3 3.5h10l-3-3.5v-6M12 13v7.5"/>',
  terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2.6"/><path d="m7 9.5 3 2.5-3 2.5M12.5 15H17"/>',
  upload: '<path d="M12 15V4m0 0L7.5 8.5M12 4l4.5 4.5M5 19.5h14"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  retake: '<path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3"/><path d="M4.5 4.5v4h4"/>',
  lockKey: '<rect x="6" y="11" width="12" height="9" rx="2.2"/><path d="M8.5 11V8.5a3.5 3.5 0 0 1 7 0V11"/>',
  close: '<path d="M7 7l10 10M17 7 7 17"/>',
  download: '<path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 19.5h14"/>',
  arrowUp: '<path d="M12 19V5m0 0-5 5m5-5 5 5"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1"/>',
  text: '<path d="M5 6.5h14M5 10.5h14M5 14.5h10M5 18.5h7"/>',
  image: '<rect x="3.5" y="5" width="17" height="14" rx="2.6"/><circle cx="9" cy="10" r="1.6"/><path d="m4 17 5-4.5 3.5 3 2.5-2 5 4"/>',
  file: '<path d="M13.5 3.5H7.6A1.6 1.6 0 0 0 6 5.1v13.8a1.6 1.6 0 0 0 1.6 1.6h8.8a1.6 1.6 0 0 0 1.6-1.6V8z"/><path d="M13.5 3.5V8H18"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.6"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
  menu: '<path d="M4.5 8.5h15M4.5 15.5h15"/>',
  menubar: '<rect x="2.5" y="4" width="19" height="16" rx="2.6"/><path d="M2.5 8.5h19"/><rect x="12.5" y="11" width="6.5" height="5.5" rx="1.4"/>',
  command: '<path d="M9 9V6.5A2.5 2.5 0 1 0 6.5 9zM15 9V6.5A2.5 2.5 0 1 1 17.5 9zM15 15v2.5a2.5 2.5 0 1 0 2.5-2.5zM9 15v2.5A2.5 2.5 0 1 1 6.5 15zM9 9h6v6H9z"/>',
  toggle: '<rect x="2.5" y="7" width="19" height="10" rx="5"/><circle cx="7.5" cy="12" r="2.6"/>',
  appearance: '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 1 0 17z" fill="currentColor"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.3 2.4 3.4 5.2 3.4 8.5s-1.1 6.1-3.4 8.5c-2.3-2.4-3.4-5.2-3.4-8.5s1.1-6.1 3.4-8.5z"/>',
  copy: '<rect x="8.5" y="8.5" width="11.5" height="11.5" rx="2.4"/><path d="M15.5 8.5V6.4A2.4 2.4 0 0 0 13.1 4H6.4A2.4 2.4 0 0 0 4 6.4v6.7a2.4 2.4 0 0 0 2.4 2.4h2.1"/>',
  share: '<path d="M12 14.5V3.5m0 0L8 7.5m4-4 4 4M8.5 10.5H7A2.5 2.5 0 0 0 4.5 13v5A2.5 2.5 0 0 0 7 20.5h10a2.5 2.5 0 0 0 2.5-2.5v-5a2.5 2.5 0 0 0-2.5-2.5h-1.5"/>',
  book: '<path d="M12 6.5C10 5.3 7.5 4.8 4 5v13c3.5-.2 6 .3 8 1.5 2-1.2 4.5-1.7 8-1.5V5c-3.5-.2-6 .3-8 1.5zM12 6.5v13"/>',
} as const;

export type IconName = keyof typeof icons;

/** The GitHub mark (Octicons, MIT), 16 × 16, filled. */
export const githubMark =
  'M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z';

/** An icon's markup, for scripts that build the notch's ears. */
export function iconSvg(name: IconName, size = 16): string {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;
}
