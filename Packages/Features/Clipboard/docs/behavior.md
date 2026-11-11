# Behavior

## Recording
- Every copy in any app is recorded while the feature is on, also with the window closed: text, a web link, an image, files.
- Text that is a single http or https address becomes a link; text with anything around it stays text.
- Files win over the icon and name Finder copies with them; an image copied in a browser stays an image.
- Copying something already in the history moves that item to the top instead of adding it again.

## Keeping
- An unpinned item goes once its last copy is older than Keep history (7, 30, 90 or 365 days; Forever never by age); copying it again, from any app or by clicking it, makes it new.
- Past 10,000 unpinned items the oldest go; past 1 GB of unpinned items (image files plus text) the oldest images go first, then, with none left, the oldest of any kind.
- Pinned items never go by time, count or size, and don't count toward either limit; a secret counts as an item that takes 0 bytes.
- Removal by time happens at launch, after each copy, when the tab shows and every hour while the feature is on.
- A shorter Keep history removes the older items at once and shows "Older items removed · Undo" for 5 s; Undo brings them and the previous choice back. Nothing older: nothing removed, no Undo.
- Clear, in the tab or in Settings, removes every unpinned item at once and shows "History cleared · Undo" for 5 s; Undo brings them back.
- Rows and image files of what Clear or a shorter time removed go only after the 5 s; if Vortex quits within them, the items are back at the next launch.
- Another Keep history within the 5 s of a shorter one first brings back what that one removed and goes back to the choice before it, then applies the new one.
- So choosing the previous time again within the 5 s works as Undo, and a new removal's Undo goes back to the choice before the first change.
- A new Clear within the 5 s makes the earlier removal final first; so does a time chosen within the 5 s of a Clear.
- An item removed and copied again within the 5 s comes back as new, with its one row; copied as a secret, it loses that row at once.
- Copies made while an ignored app was in front (since the previous check) are not recorded; what was recorded before stays.
- Copies apps mark as transient or auto-generated (nspasteboard.org, text expanders) are not recorded; what Vortex copies itself is not recorded again.
- Copies marked secret (password managers) are shown as •••• until the eye is clicked, kept in memory only and gone when Vortex quits; secret images are not recorded.
- A secret stays hidden when the same text is copied again from an app that doesn't mark it, such as the editor it was pasted into.
- Text over 2 MB and images over 30 MB are not recorded.

## The tab
- Pinned items come first, then the rest; newest first in both.
- A card shows a preview, the app it was copied in and how long ago; files go by the names Finder shows in the app's language (Downloads by its Ukrainian name in Ukrainian), extensions included.
- Clicking a card copies it again, with the marks of the app it came from, and moves it to the top; "Copied" shows once it is on the pasteboard.
- Dragging a card drops its text, link, image file or files into another app; the item stays in the history.
- A text over 4,096 bytes is held by its start: copied again, it goes whole; it drags only once the pointer has come over its card or row, which reads its whole text, and then drags whole.
- A hidden secret doesn't drag; once the eye shows it, it does.
- Hovering a card shows Pin and Delete; right click has Copy, Pin, Show in Finder (files) and Delete.
- Clear shows while there is an unpinned item and no search; the Undo toast sits under the grid.
- Files that are gone are marked "Not found", checked when the tab is shown for the newest 100 file items and for any other card as it comes on screen; such cards can't be copied or dragged.
- A card brought back by Undo, or by being copied again, keeps its "Not found" mark.
- Revealed secrets hide again every time the tab is shown.

## Search
- The field sits right of the notch, the title left of it; ⌘F focuses it, in a Ukrainian or Russian layout too.
- Esc in a non-empty field empties it; in an empty field Esc closes the window, as anywhere in the tab.
- The cards shown are the items that hold every word of the query, in any case (Ukrainian too), pinned first, newest first.
- An item is found by the first 16 KB of a text, a link's address percent-decoded, the names of files and the name of the app it was copied in; an image only by its app.
- Secrets are never found, not even by their app: they have no row to search.
- Typing pauses 150 ms before the search runs; a newer query replaces one still running. No match: "Nothing found".
- A copy, a pin or a removal while a search is shown updates the results; found cards click, drag, pin and delete as any.
- The search empties itself each time the tab is shown.

## On Home
- The clipboard sits in the dock as one-line rows of the newest 20 items, pinned first: a tiny picture for an image, an icon for any other kind, then the start of the item; secrets stay dots.
- A click copies the item again and shows a check in place of the icon, or over the picture; a row drags out; right-click has Copy, Pin and Delete.
- Secrets never drag out of Home: dropped on the shelf, one would be saved to disk.
- Dropping files, a PNG image, a link or text on it copies them: they join the history like any copy. Files dropped together are copied together.
- So a clipboard row dragged to the shelf lands on the shelf, and a shelf file dragged to the clipboard is copied.
- Dropping something the history already holds copies that item again, with its own marks, so a secret stays one; Vortex's own files and temporary ones (a screenshot dragged from its floating thumbnail) are copied as their image, never as a reference (a PNG becomes the image, any other is ignored); any other file, also a text or picture file from Finder, is copied as the file.
- Of several images dropped together (shelf tiles), only the first is copied.
- A drop before the history has been read (right after launch) is ignored.
- While Paste from Other Apps reads `notGranted`, the pasteboard isn't read at all and nothing is recorded; watching starts again when the status changes. Unknown, granted and `notNeeded` read it as always.
- macOS's `.default` pasteboard access counts as `notNeeded` (Platform's mapping, PermissionRules.swift): revisit this on macOS 27, which may start asking.
- While Vortex is blocked (a required permission is off), copies are still recorded.
