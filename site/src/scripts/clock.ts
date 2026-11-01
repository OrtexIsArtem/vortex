// The menu bar's clock shows the visitor's own date and time, as macOS does.
const clock = document.querySelector<HTMLElement>('[data-clock]');

function render(): void {
  if (!clock) return;
  const now = new Date();
  const date = now.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' }).replace(/,/g, '');
  const time = now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  clock.textContent = `${date} ${time}`;
  window.setTimeout(render, 60_000 - (now.getSeconds() * 1000 + now.getMilliseconds()) + 20);
}

render();
