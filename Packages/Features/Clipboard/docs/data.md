# Data

| What | Where | How long |
| --- | --- | --- |
| The history | table `clipboard_item` in DataFolder/vortex.sqlite | Until the item is older than Keep history, past the 10,000-item or 1 GB backstop, deleted, or cleared (5 s later) |
| Copied images | DataFolder/Clipboard/<item id>/Image <date> at <time>.png, its words in the app's language | Deleted with their item |
| Ignored apps, Keep history | DataFolder/clipboard.json | Until changed |

- DataFolder is ~/Library/Application Support/Vortex.
- `clipboard_item` columns: id, content (JSON: text, link, image file name or file URLs), source (JSON: bundle id and name), copiedAt, isPinned, isConcealed, fingerprint (SHA-256 of the content).
- Added by `clipboard.v2`, with an index on copiedAt:
  - byteSize: an image's PNG file, the UTF-8 of a text or a link, the paths of files;
  - preview: the first 4,096 bytes of a text longer than that, cut between characters; NULL for anything else;
  - searchText: the app's name on the first line, then the first 16 KB of a text, a link's address percent-decoded or the names of files, lowercased; an image has only the app's name.
- Rows saved before `clipboard.v2`, or since by an older Vortex, have byteSize 0.
- The load works out their byteSize, preview and searchText and writes them; an image's size comes from its file.

## Writes
- Each change writes only its own rows, named by id.
- A new item is inserted whole.
- A copy again or a pin updates copiedAt, source, isPinned and the app's line of searchText.
- A removal deletes rows by id.
- Content is never written after the insert.
- Writes reach the database in the order the changes were made, one batch at a time.
- An insert followed at once by a delete of the same item leaves no row.
- A batch lands whole, in one transaction, or not at all.
- A batch that fails on the database's state (busy, locked, full, read-only, I/O, can't open) stays first in the queue.
- The changes made after it join it, in order, and all are written again after a pause: 1 s, doubling, at most 60 s.
- Failed attempts are logged once per run of failures.
- A change the database refuses for good (a constraint, a value, encoding) is found by writing the batch one change at a time.
- That change alone is left out, with a line in the log; the others still go in order.
- Memory keeps a long text whole until its insert lands.
- An image folder goes once the delete of its row lands.
- Turning the feature off doesn't stop queued or retried writes.
- Writes still queued when Vortex quits are lost: the next launch shows what had landed.
- Known limit, accepted: writes wait only while the database can't be written (locked, disk full); a lost delete of a row whose text turned secret since exposes nothing new, as that text's earlier copy saved it in plain.
- Nothing is written before the saved history has been read.

## Keeping and reading
- Rows written by a newer Vortex are never changed or deleted.
- The load skips a row it can't read; a preview on anything but a text counts as unreadable.
- A saved text longer than 4,096 bytes is kept in memory by its preview.
- Its whole text is read from the database when it is copied again.
- For a drag, it is read when the pointer comes over its card or row.
- Removal by age or by the backstops deletes the rows at once.
- Clear and a shorter Keep history delete the rows when the 5 s of Undo are over.
- If Vortex quits within the 5 s of a Clear, the rows stay and the items are back.
- A shorter Keep history is saved at once: if Vortex quits within its 5 s, the next launch deletes those rows for good.
- Image folders without a row are deleted at start, unless the database is only in memory because its file didn't open.
- If the history can't be read, the session keeps it in memory only.
- Files are stored as references; nothing is copied.
- Secrets are never written to disk.
- An item that becomes a secret (the same content copied again from a password manager) loses its row at once.
- Memory then keeps its whole text again.
