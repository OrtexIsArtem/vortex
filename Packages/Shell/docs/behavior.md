# Behavior

## Opening
- Hovering the notch opens the window after the hover delay (0.3 s by default); leaving the notch earlier cancels it.
- Clicking the notch opens the window at once; clicking it again closes it.
- Hovering or clicking an ear of the closed notch opens the window on that indicator's feature (the timer's ear on the Timer tab), without changing the remembered tab.
- Hovering or clicking the cutout itself opens the last tab.
- A feature that is off, or has no tab, opens the last tab instead of its own.
- A hover counts where the pointer is when the delay ends: moving from an ear onto the cutout, or onto the other ear, before then changes the tab it opens.
- Clicking the notch of a window that opened by hover keeps it open, as if the click had opened it.
- The menu bar icon and the "Open Vortex" shortcut open and close the window.
- A feature's shortcut opens the window on its tab, or switches to it; pressed again on that tab, it closes the window.
- Dragging files, images, links or text to the notch opens the window on the first enabled feature that accepts files; with no such feature nothing happens.
- The window grows out of the notch of the screen with the pointer, flush with the top of the screen and without a shadow; on a screen without a notch it opens under the menu bar icon, with a shadow.
- The window opens on the last tab the user chose; if that feature is gone or turned off, on the first feature, then on Settings.
- Opening for dragged files does not change the remembered tab.

## Files given to Vortex
- Files dropped on the menu bar icon, or opened with Vortex (`vortex shelf add`, `open -a Vortex`), go to the first enabled feature that accepts files and the window stays as it is; without one the icon refuses the drop and opened files are ignored.

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

## Keyboard cleaning
- Home's keyboard button locks every key on the Mac: letters, modifiers, Esc, the function row and the keys for brightness, sound and media. Mouse and trackpad keep working. The window then shows only «Режим очищення клавіатури», «Усі клавіші заблоковано» and «Увімкнути клавіатуру».
- While the keys are locked, nothing closes the window: not the pointer leaving, a click outside, Esc, the notch, the menu bar icon or a shortcut. New displays move it there. Vortex comes to the front with the lock and drops any key that still reaches it.
- «Увімкнути клавіатуру» lets the keys go at once and closes the window; the app that was in front gets the front and the keys back.
- Without Accessibility the button opens Accessibility's page and locks nothing, never asking macOS itself; a lock macOS refuses opens that page too, which says to turn the switch off and on again when the status reads granted, and never closes by itself.
- Accessibility lost during a lock ends it at once and opens no page of its own; a required permission lost during a lock blocks Vortex only once the lock ends.
- macOS never lets an app lock the Touch ID (power) button or Caps Lock: Caps Lock may stay on after cleaning. If Vortex quits or crashes, the keys come back.

## Sidebar, features and permissions
- The sidebar shows enabled features in the user's order, with Settings at the bottom.
- A yellow dot on a feature's icon while a permission it needs reads `notGranted` (S22.2, S39): decoration with the tooltip "<Permission> is off"; a click on it, as on the icon, opens the tab. None before the first read, for ↻, or on Home and Settings.
- Dropping a feature's icon or settings row onto another moves it to that place; other drags are refused.
- Turning a feature off stops it (`setEnabled(false)`) and switches away from its tab; turning it on starts it again. At launch every feature is started or stopped according to the settings.
- Permission statuses are read at launch, then again on macOS's change signal, when any app becomes active and each time the window opens.
- Vortex is blocked while a required permission that an enabled feature, or keyboard cleaning with Home on, needs reads `notGranted`; becoming blocked after the launch's read (a revoke, a feature turned on, a new required set) closes the notch window and opens the blocking page.
- A feature asking for a permission's page gets the single page in the onboarding window (onboarding.md); the notch window closes first, as it does for «Продовжити налаштування».

## Settings
- Choosing another language asks for a relaunch; Restart relaunches Vortex. If Vortex hasn't quit within about 10 s, it isn't opened again.
- The menu bar icon cannot be hidden while a display without a notch is connected or while neither hover nor click opens Vortex.
- On displays without a notch the indicators appear next to the menu bar icon as text.
- When an indicator asks for it, the closed notch flashes in the color it gives: a glow spreading past the notch, behind the ears, blinking twice; over the window while it is open.
- An indicator's alarm flashes the notch, one flash after another, until the pointer comes or moves over the notch or the window opens; with the window open already it flashes three times and counts as seen; with no notch on any display it waits for one.
- Launch at login shows what the system decided; when the system wants approval, a button opens Login Items. Nothing registers it at launch: the onboarding's Basics applies "Open at login" (onboarding.md).
- Settings › General has Quit, so Vortex can be quit even with the menu bar icon hidden.
- Settings are written 0.4 s after the last change and when the app quits.
