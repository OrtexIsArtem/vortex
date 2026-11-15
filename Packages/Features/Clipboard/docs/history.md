# History

How long items stay, Clear and Undo, and search. The choice of time is in settings.md.

## Keeping
- An unpinned item goes once its last copy is older than Keep history: 7, 30, 90 or 365 days.
- Forever never removes an item by age.
- Copying an item again, from any app or by clicking it, makes it new.
- Past 10,000 unpinned items, the oldest go.
- Past 1 GB of unpinned items (image files plus text), the oldest images go first.
- When no unpinned image is left, the oldest unpinned items of any kind go; one that takes nothing (a secret) stays.
- Pinned items never go by time, count or size.
- Pinned items don't count toward the 10,000 or the 1 GB.
- A secret counts as an item that takes 0 bytes.
- Removal by time happens at launch, after each copy, when the tab shows and every hour while the feature is on.
- Removal by age or by the backstops is final at once.

## Clear, a shorter time, Undo
- A shorter Keep history removes the older items at once and shows "Older items removed · Undo" for 5 s.
- Its Undo brings the items back and the previous choice.
- A shorter time that removes nothing shows no Undo.
- Another Keep history within the 5 s of a shorter one first brings back what that one removed and the choice before it.
- Then it applies the new choice: the previous time chosen again works as Undo.
- The new removal's Undo goes back to the choice before the first change.
- Clear, in the tab or in Settings, removes every unpinned item at once and shows "History cleared · Undo" for 5 s.
- Clear's Undo brings the items back.
- A new Clear within the 5 s makes the earlier removal final first.
- A time chosen within the 5 s of a Clear lets the Clear stand: it is final first.
- What Clear or a shorter time removed keeps its rows and image files until the 5 s are over.
- If Vortex quits within the 5 s of a Clear, the items are back at the next launch.
- A shorter time is saved at once: if Vortex quits within its 5 s, the next launch removes those items for good.
- An item removed and copied again within the 5 s comes back as new, with its one row.
- Copied again as a secret within the 5 s, it loses that row at once.
- A card brought back by Undo, or by being copied again, keeps its "Not found" mark.
- A file card brought back by a drop of its files loses the mark: the drop proves they exist.

## Search
- The field sits right of the notch, the title left of it.
- ⌘F focuses it, in a Ukrainian or Russian layout too.
- Esc in a non-empty field empties it; in an empty field Esc closes the window, as anywhere in the tab.
- The cards shown are the items that hold every word of the query, in any case (Ukrainian too).
- They keep the history's order: pinned first, newest first.
- An item is found by the first 16 KB of a text, a link's address percent-decoded, the names of files and its app's name.
- An image copied since this version is also found by the first 16 KB of the text on it, once that is read (data.md).
- An older image, one never read (the history kept in memory only) or one whose reading failed or never finished is found only by its app's name.
- In an image's text, look-alike Latin and Cyrillic letters match: "mcp" finds one read as "МСР", "токен" one read as "TOKEH".
- An app's name, a text, a link or files match only as typed: "tokeh" doesn't find "токен", nor "так" "take", nor "те" an image from Terminal.
- Secrets are never found, not even by their app: they have no row to search.
- Typing pauses 150 ms before the search runs; a newer query replaces one still running.
- No match shows "Nothing found".
- A copy, a pin or a removal while a search is shown updates the results, also when the history is kept in memory only.
- Found cards click, drag, pin and delete as any.
- The tab's Clear hides while a search is shown.
- A query with no words (only spaces) is no search: Clear shows, "Nothing found" doesn't, and the cards are the whole history.
- The search empties itself each time the tab is shown.
