# Data

| What | Where | How long |
| --- | --- | --- |
| The layout: the notch row's widget, and each placed widget's size, top left cell and whether its feature is away | DataFolder/home.json (`@Shared(.homeLayout)`) | Until changed |

- No file until Home first has a widget to lay out; a missing or unreadable file means the first layout again.
- A place without `isAway` reads as a widget that shows.
- Sharing writes a change at once, and another within the same second a moment later.
- The editor's panel, search, chosen sizes and copy live in memory only, and end with the editor.
