// Real files dragged from the visitor's desktop: while they are over the page the notch opens into its drop zone, and
// dropped there they land on the shelf. Only names and sizes are read, and an image's picture is shown from the
// browser's own copy: nothing leaves this computer. Dropped anywhere else, the browser is kept from opening them.
import { inDropZone, setDropZone } from './notch';
import { putOnShelf, type Arrival } from './shelf';

let leaveTimer = 0;

const carriesFiles = (event: DragEvent) => Array.from(event.dataTransfer?.types ?? []).includes('Files');

window.addEventListener('dragover', (event) => {
  if (!carriesFiles(event)) return;
  event.preventDefault();
  const over = inDropZone(event.clientX, event.clientY) || inDropZone(event.clientX, event.clientY + 1);
  setDropZone(over ? 'hover' : 'shown');
  if (event.dataTransfer) event.dataTransfer.dropEffect = over ? 'copy' : 'none';
  // Browsers report leaving unreliably; a drag that sends no dragover for a moment has left the page.
  window.clearTimeout(leaveTimer);
  leaveTimer = window.setTimeout(() => setDropZone('off'), 220);
});

window.addEventListener('drop', (event) => {
  if (!carriesFiles(event)) return;
  event.preventDefault();
  window.clearTimeout(leaveTimer);
  const over = inDropZone(event.clientX, event.clientY);
  setDropZone('off');
  if (!over || !event.dataTransfer) return;
  const entries = Array.from(event.dataTransfer.items ?? []);
  const arrivals: Arrival[] = Array.from(event.dataTransfer.files).map((file, index) => {
    const isFolder = entries[index]?.webkitGetAsEntry?.()?.isDirectory ?? false;
    const isImage = file.type.startsWith('image/') && file.size < 20_000_000;
    return { name: file.name, size: isFolder ? null : file.size, preview: isImage ? URL.createObjectURL(file) : undefined };
  });
  putOnShelf(arrivals);
});
