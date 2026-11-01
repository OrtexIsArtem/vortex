// Renders the site's pictures from their HTML sources in this folder with a local Chrome, into public/: the social
// preview and the icons. Run from site/ after changing a source: node og/render.mjs
// (CHROME=/path/to/chrome for a browser elsewhere).
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9555;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const pictures = [
  { source: 'card.html', out: 'og.png', width: 1200, height: 630 },
  { source: 'icon.html?size=180', out: 'apple-touch-icon.png', width: 180, height: 180 },
  { source: 'icon.html?size=64', out: 'favicon-64.png', width: 64, height: 64, transparent: true },
];

const profile = mkdtempSync(join(tmpdir(), 'vortex-og-'));
const browser = spawn(
  chrome,
  ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run', '--hide-scrollbars', 'about:blank'],
  { stdio: 'ignore' },
);

try {
  for (let attempt = 0; attempt < 50; attempt++) {
    try {
      await fetch(`http://127.0.0.1:${port}/json/version`);
      break;
    } catch {
      await sleep(100);
    }
  }
  for (const picture of pictures) {
    const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
    const ws = new WebSocket(target.webSocketDebuggerUrl);
    let seq = 0;
    const pending = new Map();
    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      if (message.id && pending.has(message.id)) {
        pending.get(message.id)(message.result);
        pending.delete(message.id);
      }
    };
    await new Promise((resolve) => (ws.onopen = resolve));
    const send = (method, params = {}) =>
      new Promise((resolve) => {
        const id = ++seq;
        pending.set(id, resolve);
        ws.send(JSON.stringify({ id, method, params }));
      });
    const { width, height } = picture;
    await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
    if (picture.transparent) await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
    const [file, query = ''] = picture.source.split('?');
    await send('Page.navigate', { url: `${pathToFileURL(join(here, file)).href}${query ? `?${query}` : ''}` });
    for (let attempt = 0; attempt < 50; attempt++) {
      const ready = await send('Runtime.evaluate', { expression: "document.body?.hasAttribute('data-ready')", returnByValue: true });
      if (ready.result?.value) break;
      await sleep(100);
    }
    await sleep(200);
    const { data } = await send('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: 0, width, height, scale: 1 } });
    writeFileSync(join(here, '..', 'public', picture.out), Buffer.from(data, 'base64'));
    console.log(`public/${picture.out}  ${width} × ${height}`);
    ws.close();
  }
} finally {
  // Chrome writes its profile until it has quit.
  const exited = new Promise((resolve) => browser.once('exit', resolve));
  browser.kill();
  await exited;
  rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
