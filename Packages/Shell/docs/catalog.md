# Catalog

## What runs
- A feature runs only once added: its start, views, onboarding step, notch indicator and tab shortcut. Of one not added the shell reads only its description.
- Home is built in: always added and running, safe mode included, never stopped after a crash, never in the catalog or on the Features page.
- An added feature doesn't run before the user chooses features (a fresh install), while the maintainer pauses it (`suspension`), after a crash stopped it, or in safe mode until started.
- However what runs changes, a feature that stops gets `setEnabled(false)`, leaves the sidebar, frees its tab shortcut and hides its notch indicator; one that starts gets `setEnabled(true)`.
- The permissions Vortex asks for come from the added features, paused ones left out.

## The onboarding's Features page
- Right after Welcome, while the onboarding isn't completed: every feature but Home and the paused ones, the recommended ones checked; a check adds the feature, an uncheck removes it, without a trial.
- The footer counts the checked features and names the permissions the next pages ask for; leaving the page with Next, or closing the onboarding, starts the checked ones.

## The catalog
- The puzzle-piece icon above Settings opens the catalog in the large window; the feature icons above it scroll when there are more than fit.
- The icon has a dot while a feature is new, stopped after a crash, or waiting in safe mode.
- Added comes first, in the user's order, then Can add, the recommended ones first; an empty section doesn't show, and with nothing to add the catalog says "Everything is added".
- A card: symbol, name, one line, and the badges Recommended (Can add only), New, Beta, Stopped or Paused; an added card has the yellow dot of a permission that is off.
- Coming into the catalog marks every feature seen; the new ones keep "New" until the user leaves it.
- In safe mode the banner shows on top with "Start All", and an added card that waits has "Start".
- A card opens the feature's page; Esc on a page goes back to the list, on the list it closes the window.

## A feature's page
- The looping preview without sound, paused while the window is closed (its still with Reduce Motion, its symbol without either); the details, the permissions it needs, what it keeps and who made it.
- Not added: Add. Added: Open, "Add to Home" while none of the feature's widgets is on Home ("✓ On Home" once one is, neither without widgets), Settings (Settings › Features) and Remove. Paused: "Temporarily Unavailable" with the maintainer's reason. Stopped: Try Again and Remove. Waiting in safe mode: Start.
- Add saves at once, starts the feature on a trial and makes its tab the one the window opens on next; the window stays on the page.
- An added feature whose own setup step isn't done shows that step on its page; a permission it needs that is off shows "Turn on".
- Remove saves at once, stops the feature, leaves its tab and shows "<Name> removed · Undo" for 5 s; a permission page only it asked for closes, the blocking page stays.
- Files given to Vortex while no running feature takes them open the page of the one that would, with "Add <Name> to keep files"; once it runs it gets them (until Vortex quits).
- A feature not added that keeps data (rows in the database, its folder or its settings file) shows "Erase Data…", with the size of its folder and settings file when there is one.

## Erase Data
- It asks first, in a layer over the window: what the feature keeps, its own note (`eraseNote`), and that Vortex restarts; the window stays open meanwhile and Esc cancels.
- Confirmed, the feature goes into `pendingErase`, saved at once, and Vortex restarts.
- At launch, before any feature runs, the list is emptied and saved; then each feature on it that isn't added again loses its tables `<id>_…`, migrations `<id>.…`, `<id>.json`, folder and tab shortcut, and its own `eraseData()` runs, waited for 10 s at most.
- Erase deletes `<id>.json` and the folder only when each is one plain name (letters, digits, spaces, `-`, `_`), and never the shell's own settings, onboarding, permissions or launch file.
- A crash during an erase doesn't repeat: the list was emptied first.

## Window sizes
- The regular window is 680×440; the catalog, its pages and a feature's tab that asks for it (`windowRequest`, as Home's editor) use the large one, 880×440.
- A tab that asks for the focus dims the sidebar to 35 % and makes the other tabs and their shortcuts wait; asking for the regular window gives it back, and closing the window forgets every request.
- The large window keeps the regular one's left edge, so the sidebar stays put, and grows right; it moves left only as far as the screen's visible area needs.
- The content takes a new size at once; the outline follows with the opening's spring, or at once with Reduce Motion.
- Every open starts at the regular size on an ordinary tab: the catalog is never restored.
- Going to the catalog is a deliberate open, like a click on the notch: the pointer leaving no longer closes the window.
- Closing the window leaves the catalog.
- A leave right after the window shrank away from a still pointer isn't one.
- Right-clicking a feature's icon offers "About <Name>" (its page) and "Remove <Name>"; Home has no menu. While a menu shows, the window stays open.

## Crashes and safe mode
- Every call into a feature (starting or stopping it, handing it files, making one of its views) is marked in DataFolder/launch.json while it runs.
- A crash (SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE) writes a byte to crash.marker, 1 on the main thread and 2 on any other; Xcode's Stop, Force Quit, `scripts/qa kill` and a second copy taking over leave none and change nothing.
- After a crash on the main thread inside a call into a feature the next launch stops it; it stays added, Stopped, until Try Again. Calls run on the main thread, so a crash on another one is never blamed on them.
- A crash during one trial stops the tried feature; during several trials, inside Home, or in the first 15 s outside any call, it opens safe mode next launch.
- A crash after the first 15 s, outside any call and trial, changes nothing.
- Safe mode lasts one launch: only Home runs, Home and the catalog show the banner, and features start one by one (from a card or page) or all with "Start All".
- Add, Start, Try Again and Start All start features on a 15 s trial.
- A build other than the one that stopped features forgets them: it may have fixed the crash.
