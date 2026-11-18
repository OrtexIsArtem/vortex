# Data

| What | Where | How long |
| --- | --- | --- |
| The layout: the notch row's widget, and each placed widget's size and top left cell, and, while its feature doesn't run, the order it went in (`away`) | DataFolder/home.json (`@Shared(.homeLayout)`) | Until changed |

- The file is empty until Home first has a widget to lay out; an empty, missing or unreadable file means the first layout again.
- A place without `away` reads as a widget that shows.
- Sharing writes a change at once, and another within the same second a moment later.
- The editor changes a draft of the layout: home.json takes it at Done, in one write and only if something changed. Cancel and every other way out, quitting included, drop the draft.
- The "Add to Home" requests that waited for the editor are written as it ends, any way but quitting: at Done in the same write as the draft, and on every other way out in a write of their own, into the layout as it was.
- When a feature's widgets go or come back, home.json follows at once, the editor open or not; the draft follows on its own.
- The editor's draft, panel, search, chosen sizes and copy live in memory only, and end with the editor.
