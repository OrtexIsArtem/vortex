# Behavior

## Opening
- Hovering the notch opens the window after the hover delay (0.3 s by default); leaving the notch earlier cancels it.
- Clicking the notch opens the window at once; clicking it again closes it.
- The menu bar icon and the "Open Vortex" shortcut open and close the window.
- Dragging files to the notch opens the window on the first enabled feature that accepts files.
- The window grows out of the notch of the screen with the pointer; on a screen without a notch it opens under the menu bar icon.
- The window opens on the last tab the user chose; if that feature is gone or turned off, on the first feature, then on Settings.
- Opening for dragged files does not change the remembered tab.

## Closing
- Esc always closes the window.
- A click in another app closes the window when "Close on click outside" is on.
- A window opened by hover closes after the leave delay (0.5 s by default) once the pointer leaves it, if "Close when the pointer leaves" is on; coming back cancels.
- While something is dragged out of the window it never closes; the leave countdown starts again after the drop.
- Connecting or disconnecting a display closes the window.

## Sidebar and settings
- The sidebar shows enabled features in the user's order, with Settings at the bottom.
- Dropping a sidebar icon onto another moves it to that place; the Features section reorders by dragging too.
- Turning off the selected feature switches to the first remaining one.
- Choosing another language asks for a relaunch; Restart relaunches Vortex.
- On displays without a notch the menu bar icon is always shown, and the indicators appear next to it as text.
- On the first launch of a release build launch at login turns on; debug builds never register themselves.
- Settings are written 0.4 s after the last change and right before quitting or relaunching.
