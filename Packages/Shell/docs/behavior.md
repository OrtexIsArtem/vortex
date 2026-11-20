# Behavior

## Opening
- Hovering the notch opens the window after the hover delay (0.3 s by default); leaving the notch earlier cancels it.
- Clicking the notch opens the window at once; clicking it again closes it.
- Hovering or clicking an ear of the closed notch opens the window on that indicator's feature (the timer's ear on the Timer tab), without changing the remembered tab.
- Hovering or clicking the cutout itself, or the ear of a feature that doesn't run or of a utility, which has no tab, opens the last tab.
- A hover counts where the pointer is when the delay ends: moving from an ear onto the cutout, or onto the other ear, before then changes the tab it opens.
- Clicking the notch of a window that opened by hover keeps it open, as if the click had opened it.
- The menu bar icon and the "Open Vortex" shortcut open and close the window.
- A feature's shortcut opens the window on its tab, or switches to it; pressed again on that tab, it closes the window.
- A utility action's shortcut runs it as its button in the dock does: the window first as the action needs it (closed: an open window closes, then it runs; open; or as it is), and nothing while a utility's cover or the erase question holds the window open. While the action's permission reads `notGranted`, its page opens instead and the window doesn't open first; an open one closes.
- Dragging files, images, links or text to the notch opens the window on the first running feature that accepts files; with no such feature nothing happens.
- The window grows out of the notch of the screen with the pointer, flush with the top of the screen and without a shadow; on a screen without a notch it opens under the menu bar icon, with a shadow.
- The window opens on the Space in front, full-screen apps' Spaces included. When macOS keeps it on another full-screen Space, a new window takes its content and opens here.
- The window opens on the last tab the user chose; if that feature is gone or doesn't run, on the first feature, then on Settings. Never on the catalog (catalog.md); opening for dragged files does not change the remembered tab.
- Files dropped on the menu bar icon, or opened with Vortex (`vortex shelf add`, `open -a Vortex`), go to the first running feature that accepts files and the window stays as it is; without one the icon refuses the drop, and opened files open the page of the feature that would take them (catalog.md). On macOS 26 a drop on the icon never reaches Vortex: Control Center draws the icon.
- A window opened by hover or by dragging files does not take keyboard focus; the first click inside gives it focus. With focus, ⌘X ⌘C ⌘V ⌘A ⌘Z ⌘⇧Z work in its text fields and ⌘Q quits.

## Closing
- Esc closes a window that has keyboard focus; with the utilities dock out it puts the dock away first, and on a feature's page, in the catalog or in Settings › Features it goes back to the list first.
- A click in another app closes the window when "Close on click outside" is on.
- A window opened by hover or by dragging files closes after the leave delay (0.5 s by default) once the pointer leaves it, if "Close when the pointer leaves" is on; coming back cancels.
- Connecting or disconnecting a display closes the window.
- While something is dragged out of the window, Quick Look shows its files, the folder picker is open or a menu of Vortex shows, the window stays open; afterwards the usual rules apply.
- After the window closes under the pointer, hovering the notch counts again only once the pointer has left it.

## The utilities dock
- Home's utilities button, at the right end of its notch row, brings out a strip at the window's right, 56 pt wide (`WindowSize.dock`); growing so, the window no longer closes when the pointer leaves it.
- The strip holds the running utility actions in catalog order, a feature's own first, then the utilities', each with its shortcut's keys, read as the strip comes out, and its yellow mark while its permission reads `notGranted`; Home draws them and the pencil after them.
- The button again, Esc, a click outside the strip (on Home, in the sidebar or in another app), another tab, another window size (Home's editor) or the window closing puts the strip away; with no action left running it goes too.
- A button of the strip puts it away, then runs its action as its shortcut does.

## A utility's cover
- While a utility's cover shows (`WindowCover`, keyboard cleaning's lock screen), nothing closes the window: not the pointer leaving, a click outside, Esc, the notch, the menu bar icon or a shortcut; new displays move it there, and a cover that comes while it is closed opens it.
- With `holdsKeyboard`, Vortex is in front with the keyboard and drops every key that reaches it, handing it to the keyboard lock's presses; the app that was in front gets the front and the keys back as the cover goes.
- When the cover goes, however it ended, the window closes; a required permission that went meanwhile blocks Vortex then. A utility that stops (turned off, removed, paused) takes its cover with it, even one it left up.

## Sidebar, features and permissions
- The sidebar shows running features with a tab in the user's order; the catalog and Settings stay at the bottom, and the feature icons scroll when there are more than fit.
- A yellow dot on a feature's icon while a permission it needs reads `notGranted`: decoration with the tooltip "<Permission> is off"; a click on it, as on the icon, opens the tab. None before the first read, for ↻, or on Home and Settings.
- Dropping a feature's icon onto another moves it to that place; other drags are refused.
- Which features run, and how they are added and removed: catalog.md. At launch only running features start; nothing of the others runs, not even a stop.
- Permission statuses are read at launch, then again on macOS's change signal, when any app becomes active and each time the window opens.
- Vortex is blocked while a required permission that an enabled feature or utility needs reads `notGranted`; becoming blocked after the launch's read (a revoke, a feature added, a new required set) closes the notch window and opens the blocking page.
- A feature asking for a permission's page gets the single page in the onboarding window (onboarding.md); the notch window closes first, as it does for "Continue setup". A refused one (`openRefused`) says to turn the switch off and on again.
- After an update (a version or build other than the last launch's), the first read opens, as a feature's request does, the single page of each permission needed by an added feature or utility that macOS ties to the signature (Accessibility, Screen Recording) and reported granted under the previous version, and that now reads `notGranted`, as a new signature leaves it while System Settings still shows Vortex on; 0.1.1 and earlier kept no grants, so there it counts if Vortex had asked macOS for it. Notifications go by the bundle id and never open. Several open one after another in onboarding order, the next when one is granted or closed; checked once per version, never instead of an unfinished onboarding or the blocking page.

## Settings
- Settings › Features lists the running features in sidebar order, then the running utilities under "Utilities", each a row with its symbol, name and a chevron; with none, "Features you add with settings show them here".
- A row there has the yellow dot of the feature's sidebar icon, by the same rule and with the same tooltip; a click on it opens the page, as on the row.
- A row opens the feature's page: "‹ Features", its name, the shortcut that opens Vortex on its tab, or a utility's shortcuts of its actions, each captioned with what it does, then its own settings with their permission rows; "‹ Features" and Esc go back to the list.
- Settings remembers the open page while the app runs, as it remembers the segment; once that feature stops running, the list shows.
- Choosing another language asks for a relaunch; Restart relaunches Vortex. If Vortex hasn't quit within about 10 s, it isn't opened again.
- The menu bar icon cannot be hidden while a display without a notch is connected or while neither hover nor click opens Vortex; on displays without a notch the indicators appear next to it as text.
- When an indicator asks for it, the closed notch flashes in the color it gives: a glow spreading past the notch, behind the ears, blinking twice; over the window while it is open.
- An indicator's alarm flashes the notch, one flash after another, until the pointer comes or moves over the notch or the window opens; with the window open already it flashes three times and counts as seen; with no notch on any display it waits for one.
- "Open at login" shows what the system decided; when the system wants approval, the caption names General › Login Items & Extensions and "Open System Settings" opens it. Nothing registers it at launch: the onboarding's Basics applies the switch (onboarding.md).
- Settings › General has Quit, so Vortex can be quit even with the menu bar icon hidden, and the version (the short one, as 0.1.2); "Check for Updates" opens https://github.com/OrtexIsArtem/vortex/releases/latest in the default browser, and Vortex itself makes no network request.
- Settings are written 0.4 s after the last change and when the app quits; adding, removing, Try Again and Erase Data write them at once.
