# Data

| What | Where | How long |
| --- | --- | --- |
| The layout: the notch row's widget, and each placed widget's size and top left cell, and, while its feature doesn't run, the order it went in (`away`) | DataFolder/home.json (`@Shared(.homeLayout)`) | Until changed |

- The file is empty until Home first has a widget to lay out; an empty, missing or unreadable file means the first layout again.
- A place without `away` reads as a widget that shows.
- Sharing writes a change at once, and another within the same second a moment later.
- The editor changes a draft of the layout; home.json changes once, at Done, and only if the draft differs. Cancel and every other way out, quitting included, leave it as it was.
- The editor's draft, panel, search, chosen sizes and copy live in memory only, and end with the editor.
