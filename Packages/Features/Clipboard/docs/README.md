# Clipboard

Keeps the last ten things the user copied, plus pinned ones, and gives any of them back in one click.

| File | What it covers |
| --- | --- |
| behavior.md | what is recorded, the cards, clicks and drags, the widget on Home |
| settings.md | ignored apps |
| data.md | the history table and image files |
| contracts.md | what it takes from Core and Platform |

Code: ClipboardFeature.swift (logic, tested), ClipboardItem.swift (the item and its table), ClipboardSettings.swift,
Views/ (tab, card, Home widget, settings section), ClipboardModule.swift (entry point for the registry).
