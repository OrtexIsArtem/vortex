# Data

| What | Where | How long |
| --- | --- | --- |
| The history | table `clipboard_item` in DataFolder/vortex.sqlite | Until the item drops out of the last ten, is deleted or cleared |
| Copied images | DataFolder/Clipboard/<item id>/Image <date>.png | Deleted with their item |
| Ignored apps | DataFolder/clipboard.json | Until changed |

- DataFolder is ~/Library/Application Support/Vortex.
- `clipboard_item` columns: id, content (JSON: text, link, image file name or file URLs), source (JSON: bundle id and name), copiedAt, isPinned, isConcealed, fingerprint (SHA-256 of the content).
- The table is rewritten after every change; rows written by a newer Vortex are left untouched.
- Nothing is written before the saved history has been read, so it is never overwritten.
- Image folders without a row are deleted at start, unless the database is only in memory because its file didn't open. If the history can't be read, the session keeps it in memory only.
- Files are stored as references; nothing is copied.
- Secrets are never written to disk.
