# Behavior

- The row next to the notch shows the first `header` widget in sidebar order; without one, the title «Головна».
- `main` widgets stack in the middle, top to bottom in sidebar order.
- `dock` widgets stand side by side in a rounded panel at the bottom, in sidebar order, with hairlines between them.
- The dock is 160 pt high while the middle has widgets; otherwise it fills the height under the header.
- A turned-off feature's widget is gone; with no widgets at all, a quiet hint shows.
- The layout is fixed: widgets are not moved or resized by the user.
- A quiet keyboard button in the dock's top right corner, at the end of the widgets' title row, locks the keyboard for cleaning (the shell runs it); without a dock it sits at Home's bottom right. No button while the shell doesn't offer it.
- While Accessibility reads `notGranted`, the keyboard button shows a yellow warning with the tooltip "Accessibility is off" (S22.1); none before the first read. What a click does is the shell's.
