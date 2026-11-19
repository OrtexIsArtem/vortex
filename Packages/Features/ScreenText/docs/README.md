# Screen Text

Copies text the mouse can't select: its button in Home's utilities dock, or its shortcut, freezes the screen, a frame picks the text, and it's on the clipboard; a QR code in the frame is copied as its link or text. A utility: no tab.

| File | What it covers |
| --- | --- |
| behavior.md | the capture, what is copied, the notch's message, Esc, permissions |
| settings.md | the shortcut, the Screen Recording row |
| data.md | nothing kept |
| contracts.md | the utility action, the pasteboard copy, the clients and views it uses |

Code: ScreenTextFeature.swift (logic, tested), ScreenTextModule.swift (registry entry, utility action), ScreenTextOverlay.swift (shows the frozen screen),
Views/ (framing, settings), ScreenTextQA.swift (QA mode's `screentext` command, state, windows and fixture).
