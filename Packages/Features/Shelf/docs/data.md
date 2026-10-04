# Data

| What | Where | How long |
| --- | --- | --- |
| The shelf | table `shelf_item` in DataFolder/vortex.sqlite | 24 hours, pinned items until taken off |
| Copies (images without a file, Vortex's own files) | DataFolder/Shelf/<item id>/<name> | Deleted with their item |

- DataFolder is ~/Library/Application Support/Vortex.
- `shelf_item` columns: id, content (JSON: file URL, copy file name, text or link), addedAt, isPinned.
- The whole table is rewritten after every change, in shelf order; rows a version can't read are skipped.
- Selection, dots and file sizes live only in memory.
