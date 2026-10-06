# Behavior

## Recording
- Every copy in any app is recorded while the feature is on, also with the window closed: text, a web link, an image, files.
- Text that is a single http or https address becomes a link; text with anything around it stays text.
- Files win over the icon and name Finder copies with them; an image copied in a browser stays an image.
- Copying something already in the history moves that item to the top instead of adding it again.
- Ten items are kept; the oldest unpinned one goes when an eleventh arrives. Pinned items are not counted.
- Copies made while an ignored app was in front (since the previous check) are not recorded; what was recorded before stays.
- Copies apps mark as transient or auto-generated (nspasteboard.org, text expanders) are not recorded; what Vortex copies itself is not recorded again.
- Copies marked secret (password managers) are shown as •••• until the eye is clicked, kept in memory only and gone when Vortex quits; secret images are not recorded.
- A secret stays hidden when the same text is copied again from an app that doesn't mark it, such as the editor it was pasted into.
- Text over 2 MB and images over 30 MB are not recorded.

## The tab
- Pinned items come first, then the rest; newest first in both.
- A card shows a preview, the app it was copied in and how long ago.
- Clicking a card copies it again, with the marks of the app it came from, and moves it to the top; "Copied" shows once it is on the pasteboard.
- Dragging a card drops its text, link, image file or files into another app; the item stays in the history.
- A hidden secret doesn't drag; once the eye shows it, it does.
- Hovering a card shows Pin and Delete; right click has Copy, Pin, Show in Finder (files) and Delete.
- Clear removes everything except pinned items.
- When the tab is shown, files that are gone are marked "Not found"; such cards can't be copied or dragged.
- Revealed secrets hide again every time the tab is shown.

## On Home
- The clipboard sits in the dock as one-line rows: an icon for the kind and the start of the item; secrets stay dots.
- A click copies the item again; a row drags out; right-click has Copy, Pin and Delete.
- Secrets never drag out of Home: dropped on the shelf, one would be saved to disk.
- Dropping files, a PNG image, a link or text on it copies them: they join the history like any copy. Files dropped together are copied together.
- So a clipboard row dragged to the shelf lands on the shelf, and a shelf file dragged to the clipboard is copied.
- Dropping something the history already holds copies that item again, with its own marks, so a secret stays one; Vortex's own files are copied as their image, never as a reference (a PNG becomes the image, any other is ignored).
- Of several images dropped together (shelf tiles), only the first is copied.
- A drop before the history has been read (right after launch) is ignored.
