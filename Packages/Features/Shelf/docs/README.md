# Shelf

A place for files the user puts aside to drag into another app, as many times as needed; it clears itself after a day.

| File | What it covers |
| --- | --- |
| behavior.md | how things get on the shelf, selection, dragging out, Quick Look, expiry, the notch |
| settings.md | settings and their defaults |
| data.md | the shelf table and the shelf's own copies |
| contracts.md | files from the shell, what it takes from Core and Platform |

Code: ShelfFeature.swift (logic, tested), ShelfItem.swift (the item and its table), Views/ (tab, tile),
ShelfModule.swift (entry point for the registry: takes files).
