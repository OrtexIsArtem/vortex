# Keyboard cleaning

## The lock
- Home's keyboard button locks every key on the Mac: letters, modifiers, Esc, the function row and the keys for brightness, sound and media.
- Mouse and trackpad keep working during the lock.
- macOS never lets an app lock the Touch ID (power) button or Caps Lock: Caps Lock may stay on after cleaning.
- Without Accessibility the button opens Accessibility's page and locks nothing, never asking macOS itself.
- A lock macOS refuses opens Accessibility's page too, which says to turn the switch off and on again when the status reads granted, and never closes by itself.
- Accessibility lost during a lock ends it at once and opens no page of its own.
- A required permission lost during a lock blocks Vortex only once the lock ends.
- A lock ended before macOS took the keys never takes them afterwards.
- If Vortex quits or crashes, the keys come back.

## The window
- During the lock the window shows only the lock screen: the drawn keyboard on top, "Keyboard cleaning mode" and "All keys are locked" bottom left, "Turn the keyboard back on" bottom right.
- Nothing closes the window during the lock: not the pointer leaving, a click outside, Esc, the notch, the menu bar icon or a shortcut.
- New displays move the window there.
- Vortex comes to the front with the lock and drops any key that still reaches it.
- "Turn the keyboard back on" lets the keys go at once and closes the window.
- The app that was in front then gets the front and the keys back.

## The drawn keyboard
- It is a MacBook keyboard with English (US) labels, never translated.
- An ISO keyboard gets the ISO board: § top left, ` left of Z, a narrower left Shift and a tall Return.
- ANSI and JIS keyboards get the ANSI board.
- The board follows the keyboard used last, as macOS tells it at each lock.
- Nothing sits under the notch.
- Touch ID is drawn top right with an exclamation mark, and never washes.
- Touch ID's tooltip says not to press it: it locks the Mac, and Vortex can't block it.
- VoiceOver skips the drawing and reads the title, the subtitle and the button; the title's hint is Touch ID's warning.

## Washing
- Each lock starts every drawn key dirty.
- Each press washes its key one step; the third washes it clean, and more presses keep it clean.
- A key counts as it goes down, never on release.
- A key held down counts once, however long it repeats.
- A key pressed as the lock begins counts too.
- A modifier counts as it goes down, each side on its own.
- Caps Lock counts at each press, whichever way it turns.
- The function row's brightness, keyboard backlight, media and sound keys wash their F key.
- Mission Control, Spotlight or Launchpad, Dictation and Do Not Disturb wash their F key.
- The F keys themselves (with fn, or as standard function keys) wash their own key.
- With fn held, Home, End, Page Up and Page Down wash the arrows that send them, and Forward Delete washes delete.
- Enter washes return, whether fn+Return on a MacBook sends it or a numpad's Enter does.
- Other keys the drawing lacks wash nothing: the rest of the numpad, F13 and up, right Control.
- A key that gets past the lock into Vortex's window washes too.
- Each press nudges its key down a point; with Reduce Motion on, nothing moves.

## Privacy
- Keys are read only while the lock is on, as places on the drawing, never what they type.
- How often each key went down stays in memory and goes when the lock ends (data.md).
- The live lock never stores, logs or sends the keys; a QA run logs only the keys its commands simulate.
