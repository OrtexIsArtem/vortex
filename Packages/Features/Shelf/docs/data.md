# Data

| What | Where | How long |
| --- | --- | --- |
| The shelf | table `shelf_item` in DataFolder/vortex.sqlite | 24 hours, pinned items until taken off |
| Copies (images without a file, Vortex's own files) | DataFolder/Shelf/<item id>/<name>; an image without a file is "Image <date> at <time>", its words in the app's language | Deleted with their item |
| Watched folders and their file types, flash colors | DataFolder/shelf.json | Until changed |

- DataFolder is ~/Library/Application Support/Vortex.
- `shelf_item` columns: id, content (JSON: file URL, copy file name, text or link), addedAt, isPinned, position (shelf order, `shelf.v2`).
- The table is rewritten after every change; rows written by a newer Vortex are left untouched.
- Copy folders without a row are deleted at start, unless the database is only in memory because its file didn't open. If the shelf can't be read, the session keeps it in memory only.
- Selection, dots and file sizes live only in memory.
