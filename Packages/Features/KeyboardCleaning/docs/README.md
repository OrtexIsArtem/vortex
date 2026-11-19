# Keyboard Cleaning

Locks every key on the Mac while the keyboard is wiped: the lock screen covers the window, draws the keyboard and washes each key pressed, until "Turn the keyboard back on". A utility: no tab, a button in Home's utilities dock.

| File | What it covers |
| --- | --- |
| behavior.md | the lock, the window under the lock screen, the drawn keyboard, washing, privacy |
| settings.md | the shortcut, the Accessibility row |
| data.md | nothing kept; the presses in memory during a lock |
| contracts.md | the utility action, the window cover, the clients and views it uses |

Code: KeyboardCleaningFeature.swift (the lock, tested), KeyboardCleaningModule.swift (registry entry, utility action, cover), Views/ (lock screen, board, settings), KeyboardCleaningQA.swift (QA mode's `keyboard` command and state).
