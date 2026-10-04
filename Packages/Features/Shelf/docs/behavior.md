# Behavior

## Getting things on the shelf
- Drop files, folders, images, links or text on the tab; files dragged to the notch open the window on this tab.
- Files dropped on the menu bar icon, opened with Vortex or sent with `vortex shelf add <files>` land on the shelf without opening the window.
- Those files get a dot until the user leaves the tab, and the notch flashes once.
- Files and folders are kept by reference; images without a file are saved as PNG copies.
- Files from Vortex's own data folder (a clipboard image) are copied, since they could go away with their owner.
- Something already on the shelf moves to the front instead of being added again.
- Files that arrive before the shelf has loaded wait and are added right after.

## Watched folder
- New or changed files of the chosen types anywhere in the watched folder land on the shelf, marked with a dot; the notch flashes.
- A file lands once it is fully written: its size has stayed the same for 1.5 s and it changed no more meanwhile.
- Files that vanish while being written (temporary files renamed by the build tool) are skipped; hidden files too.
- Files already in the folder are not added; watching runs only while the feature is on.

## On the shelf
- Newest first. A tile shows a preview (Quick Look thumbnail, or the extension), the name, size or "Folder", and age.
- Click selects, ⌘-click adds or removes, ⇧-click selects a range, a click on empty space clears the selection.
- Dragging a selected item drags the whole selection; an unselected item is dragged alone. Items stay on the shelf.
- Double click opens the file in its app, or the link in the browser.
- Space shows the selection in Quick Look and hides it again; ⌫ takes the selection off the shelf; ⌘A selects all.
- Right click: Quick Look, Show in Finder, Pin, Remove from the shelf. × on hover removes.
- Clear takes everything off except pinned items. Taking something off never touches the user's files.
- When the tab is shown, missing files are marked "Not found" and can't be dragged or previewed.

## Expiry and the notch
- Unpinned items leave the shelf 24 hours after they were added, checked every 10 minutes and at start.
- While the shelf has items, the closed notch shows a tray and their number; turning the feature off hides it.
