# Clipboard

Keeps what the user copied for the time they choose (a month by default), plus pinned ones, finds any of it by search and gives it back in one click.

| File | What it covers |
| --- | --- |
| behavior.md | what is recorded, the cards, clicks and drags, the widget on Home |
| history.md | how long items stay, Clear and Undo, search |
| settings.md | Keep history, the History row, ignored apps |
| data.md | the history table, its writes and image files |
| contracts.md | what it takes from Core and Platform |

Code: ClipboardFeature.swift (logic, tested), ClipboardItem.swift (the item, its table and writes), ClipboardSettings.swift, LinkAddress.swift,
Views/ (tab, card, Home widget, settings section, Undo toast), ClipboardModule.swift (registry entry), ClipboardQA.swift (QA mode's `clipboard` command).
