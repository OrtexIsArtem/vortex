# Behavior

How long items stay, Clear with Undo, and search are in history.md.

## Recording
- Every copy in any app is recorded while the feature is on, also with the window closed: text, a web link, an image, files.
- Text that is a single http or https address becomes a link; text with anything around it stays text.
- Files win over the icon and name Finder copies with them.
- An image copied in a browser stays an image.
- Copying something already in the history moves that item to the top instead of adding it again.
- Copies made while an ignored app was in front (since the previous check) are not recorded.
- What was recorded before an app was ignored stays.
- Copies apps mark as transient or auto-generated (nspasteboard.org, text expanders) are not recorded.
- What Vortex copies itself is not recorded again.
- Copies marked secret (password managers) are shown as •••• until their own eye, Show, is clicked; Quick Look never shows them.
- Secrets are kept in memory only and are gone when Vortex quits.
- Secret images are not recorded.
- A secret stays hidden when the same text is copied again from an app that doesn't mark it, such as the editor it was pasted into.
- Text over 2 MB and images over 30 MB are not recorded.

## The tab
- Pinned items come first, then the rest; newest first in both.
- A card shows a preview, the app it was copied in and how long ago.
- Files go by the names Finder shows in the app's language (Downloads by its Ukrainian name in Ukrainian), extensions included.
- Clicking a card copies it again, with the marks of the app it came from, and moves it to the top.
- "Copied" shows once the item is on the pasteboard.
- Link cards, Home rows, Quick Look and VoiceOver show a link's address with letters beyond ASCII decoded (`/привіт`); ASCII escapes (`%20`), escapes that don't spell a letter and invisible characters stay as written.
- Copying a link gives it as it was.
- Dragging a card drops its text, link, image file or files into another app; the item stays in the history.
- A text over 4,096 bytes is held by its start; copied again, it goes whole.
- It drags only once the pointer has come over its card or row, which reads its whole text; then it drags whole.
- A hidden secret doesn't drag; once Show reveals it, it does.
- Hovering a card shows Quick Look's eye, Pin and Delete; right click has Copy, Quick Look, Pin, Show in Finder (files) and Delete.
- Quick Look shows an image's PNG, the files, or a text or a link whole, from a .txt in Vortex's temporary folder.
- Space shows the card under the pointer in Quick Look and closes it again, unless the search field has the keyboard.
- Quick Look closes when the tab or the window hides, and the .txt files go; while it shows, the window stays open.
- Clear shows while there is an unpinned item; the Undo toast sits under the grid.
- Files that are gone are marked "Not found"; such cards can't be copied, dragged or shown in Quick Look.
- Files are checked for the newest 100 file items when the tab is shown, for any other card as it comes on screen, and before Quick Look shows them.
- Revealed secrets hide again every time the tab is shown.

## On Home
- The clipboard sits in the dock as one-line rows: at most 10 pinned items, newest first, then the newest unpinned ones, 20 rows in all.
- Pinned items past those 10 show only in the tab, even when Home has room for them.
- A row shows a tiny picture for an image or an icon for any other kind, then the start of the item; secrets stay dots.
- A click copies the item again and shows a check in place of the icon, or over the picture.
- A row drags out; under the pointer Quick Look's eye shows at its end; right-click has Copy, Quick Look, Pin and Delete.
- Secrets never drag out of Home: dropped on the shelf, one would be saved to disk.
- Dropping files, a PNG image, a link or text on it copies them: they join the history like any copy.
- Files dropped together are copied together.
- So a clipboard row dragged to the shelf lands on the shelf, and a shelf file dragged to the clipboard is copied.
- Dropping something the history already holds copies that item again, with its own marks, so a secret stays one.
- Vortex's own files and temporary ones (a screenshot dragged from its floating thumbnail) are copied as their image: a PNG becomes the image, any other is ignored.
- Any other file, also a text or picture file from Finder, is copied as the file.
- Of several images dropped together (shelf tiles), only the first is copied.
- A drop before the history has been read (right after launch) is ignored.
- While Paste from Other Apps reads `notGranted`, the pasteboard isn't read and nothing is recorded; watching starts again when it changes.
- Unknown, granted and `notNeeded` read the pasteboard as always.
- macOS's `.default` pasteboard access counts as `notNeeded` (Platform's mapping, PermissionRules.swift): revisit this on macOS 27, which may start asking.
- While Vortex is blocked (a required permission is off), copies are still recorded.
