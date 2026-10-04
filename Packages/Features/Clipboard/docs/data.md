# Data

| What | Where | How long |
| --- | --- | --- |
| The history | table `clipboard_item` in DataFolder/vortex.sqlite | Until the item drops out of the last ten, is deleted or cleared |
| Copied images | DataFolder/Clipboard/<item id>/Image <date>.png | Deleted with their item |
| Ignored apps | DataFolder/clipboard.json | Until changed |

- DataFolder is ~/Library/Application Support/Vortex.
- `clipboard_item` columns: id, content (JSON: text, link, image file name or file URLs), source (JSON: bundle id and name), copiedAt, isPinned, isConcealed, fingerprint (SHA-256 of the content).
- The whole table is rewritten after every change; rows a version can't read are skipped.
- Files are stored as references; nothing is copied.
- Secrets are stored like any other text.
