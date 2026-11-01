/** Sizes of the Vortex app's notch window (VortexMetrics, EarsMetrics and GlowMetrics in the app). */
export const metrics = {
  window: { width: 680, height: 440, radius: 30, shoulder: 10 },
  notchRadius: 10,
  ears: { padding: 14, spacing: 6, icon: 16, radius: 14 },
  glow: { spread: 130, depth: 100 },
  header: 52,
  sidebar: 56,
} as const;

export interface Outline {
  width: number;
  height: number;
  radius: number;
  shoulder: number;
}

const f = (n: number) => +n.toFixed(2);

/**
 * The app's HangingShape (Packages/Shell/Sources/Window/WindowChromeView.swift), centered on `cx`: it hangs from the
 * top edge, with concave shoulders where it meets the edge and rounded bottom corners. Open, it leaves out the top
 * edge, which is what an outline along the shape needs.
 */
export function hangingPath({ width, height, radius, shoulder }: Outline, closed = true, cx = 0): string {
  const left = cx - width / 2;
  const right = cx + width / 2;
  const corner = Math.max(0, Math.min(radius, width / 2, height / 2));
  const s = Math.max(0, shoulder);
  let d = `M${f(left - s)} 0`;
  if (s > 0) d += `A${f(s)} ${f(s)} 0 0 1 ${f(left)} ${f(s)}`;
  d += `L${f(left)} ${f(height - corner)}`;
  if (corner > 0) d += `A${f(corner)} ${f(corner)} 0 0 0 ${f(left + corner)} ${f(height)}`;
  d += `L${f(right - corner)} ${f(height)}`;
  if (corner > 0) d += `A${f(corner)} ${f(corner)} 0 0 0 ${f(right)} ${f(height - corner)}`;
  d += `L${f(right)} ${f(s)}`;
  if (s > 0) d += `A${f(s)} ${f(s)} 0 0 1 ${f(right + s)} 0`;
  return closed ? `${d}Z` : d;
}
