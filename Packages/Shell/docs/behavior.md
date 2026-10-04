# Behavior

## Opening
- Hovering the notch opens the window after the hover delay (0.3 s by default); leaving the notch earlier cancels it.
- Clicking the notch opens the window at once; clicking it again closes it.
- Clicking the notch of a window that opened by hover keeps it open, as if the click had opened it.
- The menu bar icon and the "Open Vortex" shortcut open and close the window.
- A feature's shortcut opens the window on its tab, or switches to it; pressed again on that tab, it closes the window.
- Dragging files, images, links or text to the notch opens the window on the first enabled feature that accepts files; with no such feature nothing happens.
- The window grows out of the notch of the screen with the pointer; on a screen without a notch it opens under the menu bar icon.
- The window opens on the last tab the user chose; if that feature is gone or turned off, on the first feature, then on Settings.
- Opening for dragged files does not change the remembered tab.

## Files given to Vortex
- Files dropped on the menu bar icon, or opened with Vortex (`vortex shelf add`, `open -a Vortex`), go to the first enabled feature that accepts files; the window stays as it is.
- Without such a feature the menu bar icon refuses the drop and opened files are ignored.

## Keyboard
- A window opened by hover or by dragging files does not take keyboard focus; the first click inside gives it focus.
- With focus, ⌘X ⌘C ⌘V ⌘A ⌘Z ⌘⇧Z work in its text fields and ⌘Q quits.

## Closing
- Esc closes a window that has keyboard focus.
- A click in another app closes the window when "Close on click outside" is on.
- A window opened by hover or by dragging files closes after the leave delay (0.5 s by default) once the pointer leaves it, if "Close when the pointer leaves" is on; coming back cancels.
- Connecting or disconnecting a display closes the window.
- While something is dragged out of the window, Quick Look shows its files or the folder picker is open, the window stays open; afterwards the usual rules apply.
- After the window closes under the pointer, hovering the notch counts again only once the pointer has left it.

## Sidebar and features
- The sidebar shows enabled features in the user's order, with Settings at the bottom.
- Dropping a feature's icon or settings row onto another moves it to that place; other drags are refused.
- Turning a feature off stops it (`setEnabled(false)`) and switches away from its tab; turning it on starts it again.
- Every feature is started or stopped at launch according to the settings.

## Settings
- Choosing another language asks for a relaunch; Restart relaunches Vortex.
- The menu bar icon cannot be hidden while a display without a notch is connected or while neither hover nor click opens Vortex.
- On displays without a notch the indicators appear next to the menu bar icon as text.
- When an indicator asks for it, the closed notch flashes once.
- Launch at login shows what the system decided; when the system wants approval, a button opens Login Items.
- On the first launch of a release build launch at login turns on; debug builds never register themselves.
- Settings › General has Quit, so Vortex can be quit even with the menu bar icon hidden.
- Settings are written 0.4 s after the last change and when the app quits.
