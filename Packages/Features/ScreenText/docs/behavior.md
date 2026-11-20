# Behavior

## Capture
- The shortcut (none by default, set on the settings page) runs the utility action "Copy Text"; the shell runs it, its window closed first, so the frozen screen and the notch's message never sit over or behind it.
- The shell will also place the action's button; until then the shortcut is the way in.
- The app in front is noted, then the display under the pointer is taken and freezes; Vortex's own windows aren't on it.
- The notch shows "Screen Text · Esc"; "Frame the text · Esc to cancel" shows above the Dock.
- Dragging draws the frame, with a crosshair pointer; outside it the screen dims.
- Letting go reads the frame: the frame stays, the hint says "Reading the text…", then the frozen screen goes.
- A frame under 8 pt either way, as a click makes, or one off the screen, ends the capture quietly: nothing read, said or copied.
- A press while a capture is under way does nothing.
- While another capture's frozen screen shows, as Tasks', the shortcut does nothing; of two started together, the second gives way.
- Another app coming to the front ends the capture.

## What is copied
- A QR code first: what it holds, as it spells it, the largest code when there are several.
- An http or https address in a code is "Link copied · host": the host as the code spells it, in lower case, without "www.", and past 24 characters cut in the middle.
- Anything else in a code is "Copied · QR code".
- A Wi-Fi network (`WIFI:`) or a one-time code's secret (`otpauth://`, `otpauth-migration://`) is copied hidden from clipboard histories (concealed); the notch never shows it.
- No code: the lines of text, top to bottom, joined by line breaks; a line's pieces on one row (a message and its time, a line number and its line) joined by a space; blank lines and spaces around them go. "Copied · 2 lines" counts these lines, plurals in en and uk.
- Nothing found: "No text found", and the pasteboard stays as it was.
- The copy is the user's own: Clipboard keeps it by its rules, named after the app that was in front when the screen froze; a copy over an app Clipboard ignores isn't kept, but is still on the pasteboard.
- Text and codes are read on this Mac by Apple Vision (English, Ukrainian, Russian), off the main thread, ahead of other features' reads waiting in the background, as Tasks' and Clipboard's.
- Text is read without language correction, which would make `Main.swift:42` into `Main.swift: 42`; what Vision itself misreads in small text stays as it read it.
- Words keep their spaces: a second read, with correction, gives the spaces between two lowercase letters that the first lost in small text ("brownfox"), and nothing else, so a camelCase word (`querySelector`) stays whole.
- As the screen freezes, Vision warms up with a tiny read in the background while the frame is drawn, so the first read after a launch waits less; nothing keeps it warm otherwise.
- A frame over 1,600 px either way is read in overlapping tiles at full resolution, so small text in a frame as wide as the screen is read whole, each line once.

## The notch's message
- It shows about 1.5 s in the closed notch's ears, then goes; nothing opens and nothing flashes.
- A new message takes the place of the one showing, with its own 1.5 s.
- It comes before Timer's and the shelf's ears, after Keys' waiting approval.
- Where no display has a notch, it is the menu bar icon's text.
- Its ear opens the window on the last tab: Screen Text has none.
- Stopping the feature, as Remove does, takes it away; it never comes back after Undo.

## Esc
- Esc cancels at every step: before the drag, during it, and while the frame is read; nothing is copied or said.
- Esc while the frame is read stops Vision too, so the next capture's read doesn't wait for it.
- The mouse let go after Esc reads nothing.

## Permissions
- With Screen Recording `notGranted` or granted only from the next launch, the shortcut opens the shell's Screen Recording page and takes nothing.
- Before the shell's first read a press waits for it, then decides; while Vortex is blocked, a press opens the page.
- Screen Text never asks macOS itself; a capture under way finishes.
