# Data

| What | Where | How long |
| --- | --- | --- |
| The shelf | table `shelf_item` in DataFolder/vortex.sqlite | 24 hours, pinned items until taken off |
| Copies (images without a file, Vortex's own files) | DataFolder/Shelf/<item id>/<name> | Deleted with their item |
| Watched folders and their file types | DataFolder/shelf.json | Until changed |

- DataFolder is ~/Library/Application Support/Vortex.
- `shelf_item` columns: id, content (JSON: file URL, copy file name, text or link), addedAt, isPinned, position (shelf order, `shelf.v2`).
- The table is rewritten after every change; rows written by a newer Vortex are left untouched.
- Copy folders without a row are deleted at start. If the shelf can't be read, the session keeps it in memory only.
- Selection, dots and file sizes live only in memory.
