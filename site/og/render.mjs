// Renders the site's pictures from their HTML sources in this folder with a local Chrome, into public/: the social
// preview and the icons. Run from site/ after changing a source: node og/render.mjs, or name the files to redraw
// only them (node og/render.mjs favicon.ico); CHROME=/path/to/chrome for a browser elsewhere.
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
  // For the browsers and services that ask for /favicon.ico whatever the page links.
  { source: 'icon.html?size=48', out: 'favicon.ico', width: 48, height: 48, transparent: true, ico: true },
];

/** A PNG wrapped in an ICO container, which every current browser reads. */
function ico(png, size) {
  const header = Buffer.alloc(6 + 16);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // icon
  header.writeUInt16LE(1, 4); // one image
  header.writeUInt8(size, 6); // width
  header.writeUInt8(size, 7); // height
  header.writeUInt8(0, 8); // no palette
  header.writeUInt8(0, 9); // reserved
  header.writeUInt16LE(1, 10); // color planes
  header.writeUInt16LE(32, 12); // bits per pixel
  header.writeUInt32LE(png.length, 14);
  header.writeUInt32LE(header.length, 18);
  return Buffer.concat([header, png]);
}

const profile = mkdtempSync(join(tmpdir(), 'vortex-og-'));
const browser = spawn(
  chrome,
  ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--no-first-run', '--hide-scrollbars', 'about:blank'],
  { stdio: 'ignore' },
);

try {
  // Chrome can take several seconds to start.
  for (let attempt = 0; attempt < 150; attempt++) {
    try {
      await fetch(`http://127.0.0.1:${port}/json/version`);
      break;
    } catch {
      await sleep(100);
    }
  }
  const only = process.argv.slice(2);
  for (const picture of pictures.filter((picture) => !only.length || only.includes(picture.out))) {
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
    const png = Buffer.from(data, 'base64');
    writeFileSync(join(here, '..', 'public', picture.out), picture.ico ? ico(png, width) : png);
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
