# Clipboard

Keeps what the user copied for the time they choose (a month by default), plus pinned ones, finds any of it by search and gives it back in one click.

| File | What it covers |
| --- | --- |
| behavior.md | what is recorded, how long it is kept, the cards, clicks and drags, search, the widget on Home |
| settings.md | Keep history, the History row, ignored apps |
| data.md | the history table and image files |
| contracts.md | what it takes from Core and Platform |

Code: ClipboardFeature.swift (logic, tested), ClipboardItem.swift (the item, its table and its writes),
ClipboardSettings.swift, Views/ (tab, card, Home widget, settings section, Undo toast), ClipboardModule.swift (entry
point for the registry), ClipboardQA.swift (QA mode's `clipboard` command and seed, debug builds only).
