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
- Rows saved before `clipboard.v2`, or since by an older Vortex, have byteSize 0: the load works these columns out and writes them, an image's size from its file.
- Each change writes only its own rows: a new item is inserted whole, a copy again or a pin updates copiedAt, source, isPinned and the app's line of searchText, a removal deletes by id. Content is never written again.
- Writes reach the database in the order the changes were made, one batch at a time: an insert followed at once by a delete of the same item leaves no row.
- Rows written by a newer Vortex are never changed or deleted: every write names its rows by id, and a row the load can't read (or a preview on anything but a text) is skipped.
- A saved text longer than 4,096 bytes is kept in memory by its preview; its whole text is read from the database when it is copied again, and for a drag when the pointer comes over its card or row.
- Removal by age or by the backstops deletes the rows at once; Clear and a shorter Keep history delete them after the 5 s of Undo, so rows stay if Vortex quits within them.
- Nothing is written before the saved history has been read.
- Image folders without a row are deleted at start, unless the database is only in memory because its file didn't open. If the history can't be read, the session keeps it in memory only.
- An image folder goes once its row is gone.
- Files are stored as references; nothing is copied.
- Secrets are never written to disk. An item that becomes a secret (the same content copied again from a password manager) loses its row at once, and memory keeps its whole text again.
