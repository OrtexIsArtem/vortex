# Behavior

## The grid
- Home is a row next to the notch and a grid of 4×2 cells of 143×182 pt, 12 pt apart, 8 pt from the sides, 12 pt from the bottom.
- On a notch wider than 186 pt the window is wider: the row spans it, and the grid keeps its size in the middle, the extra room equal margins at its sides.
- A widget takes Small 1×1, Medium 2×1, Wide 4×1, Large 2×2 or Full 4×2 cells, or the notch row; its view gets its size from `homeWidgetSize`.
- Widgets never overlap and stay inside the grid; the notch row holds one widget, or the title "Home".
- With no widget on the grid, outside the editor, the grid says so in its middle, with an Edit Home button: "No widgets on Home", or "No widgets on Home's grid" while a widget is in the notch row.

## The first layout
- Home lays itself out once the running features offer a widget: the first notch row widget in sidebar order goes to the row; each other widget, in sidebar order, at its first size that fits, in the first free place, left to right, then top to bottom; one that fits nowhere stays off.
- Before the user chooses features no widget runs, so no layout is saved.
- A feature added later doesn't put its widget on Home by itself; its page offers "Add to Home".

## Features that go and come back
- A feature that stops or is removed takes its widget off Home; the widget stays in the layout, away, and its place is free.
- A widget that comes back shows in its place again if no widget that shows took it; otherwise it leaves the layout.
- Widgets that come back together, as after safe mode, go in the reverse order they went: the one that showed last keeps a contested place.
- Home follows the widgets the shell tells it whether its tab shows or not; at launch it changes nothing until the shell first tells them.

## The editor
- The pencil (the utilities strip's last button, or the notch row's button itself while no utility runs), Home's right-click menu and the empty grid's button open the editor.
- The editor asks for the large window with the focus: the window grows right by the panel's 200 pt, to 880 on most notches, and the sidebar dims and waits.
- In the editor widgets don't answer the pointer, and free cells show dashed.
- Under the pointer, or with the keyboard's focus (Tab), a widget has a 1 pt ring and "−" at its top left; "−" or Delete removes it.
- A dragged widget lands with its top left corner on the nearest cell, and the widgets in its way move aside.
- Each moves by the reverse of the drag, so they keep how they lay; where the two swap whole, that is the place it left. One that doesn't fit there, as on a partial overlap, goes to the free place nearest its own, the first in reading order among places as near: a Medium dragged one cell right onto the Small next to it sends the Small one cell right, not to where the Medium was.
- Widgets not in its way move only when that is the only way to make room; where the others can't all fit, it goes back and nothing moves.
- While it is dragged, the widgets in its way already slide where they would go, an outline shows where it lands, and the dashed free cells follow; the drop keeps exactly that.
- An away widget takes no part in a drag: its place is free, and it keeps it; the notch row stays as it is.
- The panel on the right: Cancel and Done, a search of feature and widget names in any case, "On Home" and "More" in sidebar order, and "More widgets in Features", which is Done, then the catalog.
- A feature's row says "N widgets · M on Home", "1 widget · on Home", "N widgets" or "In the notch row", and opens the feature's widgets.
- A widget in the panel: its preview, laid out at its real size and scaled down (a notch row widget as wide as the row), its name, "On Home", "No room" or Add, and its sizes as chips: "2×1".
- On Home a size applies in place, keeping the top left corner, and only if it fits there; a size that doesn't is dimmed.
- Off Home a size is chosen for Add, and under the pointer the widget's copy shows at its real size, faint and dashed, where Add would put it, named "Files · 2×1".
- Without room the panel says "No room" and "Remove a widget or choose a smaller size."
- A notch row widget's copy shows in the row while it is free, and Add puts it there.
- Nothing the editor changes is kept until Done, which keeps every edit.
- Cancel puts Home back as it was when the editor opened; so does every other way out: Esc, a click outside, a shortcut, the menu bar icon, the window closing any other way, leaving the tab (the menu bar's Settings), quitting.
- However the editor ends, the window goes back to regular; the next open is regular too.
- The editor's large window is a deliberate open: it doesn't close when the pointer leaves it.
- A feature that goes or comes back while the editor is open changes what is saved and the editor's draft alike, each by the rules above, so Done and Cancel both leave a layout that follows them.

## Add to Home
- "Add to Home" on a feature's page puts its first widget on Home: in the notch row while it is free, or at its first size that fits in the first free place; without room Home stays as it is and tells the shell, whose page says "No room on Home".
- Once the first widget would fit, as when another widget goes, Home tells the shell, and "No room on Home" goes; Home doesn't put the widget there by itself.
- An "Add to Home" that comes while the editor is open waits for it to end, then goes into the layout kept.
- Home tells the shell which features have a widget on it as saved: their pages say "On Home"; the editor's edits count once Done keeps them.

## The utilities button and its strip
- The notch row ends in a 44 pt slot for the utilities button, a 28 pt circle 8 pt from the window's edge, after the row widget's controls (the timer's Start), so the notch stays in the window's middle; without a row widget it sits at the row's end, right of Home's title. It hides in the editor.
- With no utility running the button is the pencil, Edit Home itself; otherwise it brings out the strip, which the shell sizes, and is lit while the strip is out; a yellow dot on it while a button of the strip has its warning.
- The strip, 56 pt at the window's right on the panel's shade: the dock's buttons in one column, the first beside the row's button, 28 pt circles in 44 pt targets, each with its tooltip, its label and its shortcut's keys, and a yellow warning while its permission is off; then, after a short line, the pencil.
- A button puts the strip away and runs as the shell runs it; a click anywhere else on Home puts it away and does nothing more; the pencil opens the editor, whose window takes the strip's place.
- Home's bottom right corner holds no button of its own: the grid reaches the window's edge.

## Targets
- The utilities button, the strip's buttons, the panel's size chips, Add, "‹ Widgets", "More widgets in Features" and the search's clear button take clicks past what they draw, toward 44 pt, into room no other control's target takes; nothing they draw moves (HomeTargetsTests).
