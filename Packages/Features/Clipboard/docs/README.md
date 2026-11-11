# Clipboard

Keeps what the user copied for the time they choose (a month by default), plus pinned ones, and gives any of it back in one click.

| File | What it covers |
| --- | --- |
| behavior.md | what is recorded, how long it is kept, the cards, clicks and drags, the widget on Home |
| settings.md | Keep history, the History row, ignored apps |
| data.md | the history table and image files |
| contracts.md | what it takes from Core and Platform |

Code: ClipboardFeature.swift (logic, tested), ClipboardItem.swift (the item and its table), ClipboardSettings.swift,
Views/ (tab, card, Home widget, settings section), ClipboardModule.swift (entry point for the registry).
