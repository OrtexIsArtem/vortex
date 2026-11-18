# Behavior

## The grid
- Home is a row next to the notch and a grid of 4×2 cells of 143×182 pt, 12 pt apart, 8 pt from the sides, 12 pt from the bottom.
- A widget takes Small 1×1, Medium 2×1, Wide 4×1, Large 2×2 or Full 4×2 cells, or the notch row; its view gets its size from `homeWidgetSize`.
- Widgets never overlap and stay inside the grid; the notch row holds one widget, or the title "Home".
- With no widget on Home it says "No widgets on Home", with an Edit Home button.

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
- The pencil in the bottom right corner, Home's right-click menu and the empty Home's button open the editor.
- The editor asks for the large window with the focus: the window grows right to 880 pt, and the sidebar dims and waits.
- In the editor widgets don't answer the pointer, and free cells show dashed.
- Under the pointer, or with the keyboard's focus (Tab), a widget has a 1 pt ring and "−" at its top left; "−" or Delete removes it.
- A dragged widget lands with its top left corner on the nearest cell, and the widgets in its way move aside.
- They first take the place it left, each moved by the reverse of the drag, so they keep how they lay; one that doesn't fit there goes to the nearest free place.
- Widgets not in its way move only when that is the only way to make room; where the others can't all fit, it goes back and nothing moves.
- While it is dragged, the widgets in its way already slide where they would go, an outline shows where it lands, and the dashed free cells follow; the drop keeps exactly that.
- An away widget takes no part in a drag: its place is free, and it keeps it; the notch row stays as it is.
- The panel on the right: Done, a search of feature and widget names in any case, "On Home" and "More" in sidebar order, and "More widgets in Features", which ends the editor and opens the catalog.
- A feature's row says "N widgets · M on Home", "1 widget · on Home", "N widgets" or "In the notch row", and opens the feature's widgets.
- A widget in the panel: its preview, its name, "On Home", "No room" or Add, and its sizes as chips: "2×1".
- On Home a size applies in place, keeping the top left corner, and only if it fits there; a size that doesn't is dimmed.
- Off Home a size is chosen for Add, and under the pointer the widget's copy shows at its real size, faint and dashed, where Add would put it, named "Files · 2×1".
- Without room the panel says "No room" and "Remove a widget or choose a smaller size."
- A notch row widget's copy shows in the row while it is free, and Add puts it there.
- Edits are saved at once. Done, closing the window (Esc, a click outside, a shortcut, the menu bar icon) or leaving the tab ends the editor; the next open is regular.

## Add to Home
- "Add to Home" on a feature's page puts its first widget on Home: in the notch row while it is free, or at its first size that fits in the first free place; without room nothing happens.
- Home tells the shell which features have a widget on it: their pages say "On Home".

## The corner buttons
- A capsule in Home's bottom right corner holds the keyboard button, while the shell offers it, and the pencil; it hides in the editor.
- The keyboard button locks the keyboard for cleaning: what a click does is the shell's.
- While Accessibility reads `notGranted`, the keyboard button shows a yellow warning with the tooltip "Accessibility is off"; none before the first read.
