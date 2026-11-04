# Behavior

## Getting things on the shelf
- Drop files, folders, images, links or text on the tab; files dragged to the notch open the window on this tab.
- A file always lands as the file, also a text or picture file from Finder, never as its contents.
- Files dropped on the menu bar icon, opened with Vortex or sent with `vortex shelf add <files>` land on the shelf without opening the window. On macOS 26 a drop on the icon never reaches Vortex (Control Center draws the icon), so the shelf doesn't offer it.
- Those files get a dot until the user leaves the tab, and the notch flashes: a glow that spreads past its edges,
  blinking twice. Its color follows the number of new files: color 1 for the first, color 2 for the second… then white.
- Looking at the shelf (leaving its tab) starts the count over; files dropped on the tab do not flash.
- Only a look counts: the window opening on another tab, for example from another feature's ear, keeps the dots and the count.
- Files and folders are kept by reference; images without a file are saved as PNG copies.
- Files from Vortex's own data folder (a clipboard image) are copied, since they could go away with their owner; so are files from temporary folders (a screenshot dragged from its floating thumbnail), which go once the drag is over.
- Such a file dropped again moves its copy to the front instead of being copied again; copies are matched by file name.
- The same file, folder, text or link moves to the front instead of being added again; images without a file are added each time.
- Whatever arrives before the shelf has loaded waits and is added right after, so the saved shelf is never overwritten.

## Watched folders
- Build files get a new name every time, so the shelf watches folders instead: new or changed files of a folder's types, anywhere inside it, land on the shelf with a dot; the notch flashes.
- A file lands once it is fully written: its size stayed the same over two checks a second apart, with no change meanwhile.
- Files of a folder moved in land too. Hidden files and folders, and the insides of packages (apps, partial downloads), are skipped.
- Files that vanish while being written (temporary files renamed by the build tool) and empty files that stay empty are skipped.
- Files already in a folder are not added; watching runs only while the feature is on.

- The empty shelf says unpinned items leave after 24 hours, offers Watch a folder… and names the folders it already watches, as Finder names them in the app's language: "New files from %@ appear here by themselves." for one folder, "New files from these folders appear here by themselves: %@." for several.

## On the shelf
- Newest first. A tile shows a preview (Quick Look thumbnail, or the extension), the name as Finder shows it in the app's language with the extension kept, size or "Folder", and age.
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

## On Home
- The shelf sits in the dock as small tiles with their names; the last tile takes drops.
- Tiles drag out, open on double-click and have the same menu as in the tab; the whole widget takes drops.
- While the window shows Home, the shelf counts as seen: fresh marks and the flash count start over when it closes.
