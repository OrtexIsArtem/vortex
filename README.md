# Vortex

A macOS utility that lives in your MacBook's notch, or in the menu bar on a Mac without one. Hover over the notch and it opens with the tools you reach for a dozen times a day.

- **Timer**: set the minutes on a drum, and watch the countdown in the notch. When time is up, it plays a sound, flashes and shows a notification.
- **Clipboard**: your last copies plus pinned ones. Text, links, images and files.
- **Shelf**: put files aside and drag them out later, into any app. Unpinned files clear after a day.
- **Tasks**: a shortcut freezes the screen; frame an area and press Return. You get a task with the screenshot, its recognized text and the page address from your browser.
- **Keys for Claude**: keep database URLs, API tokens and passwords in the macOS keychain. Claude Code runs commands with `{{key}}` placeholders through a local MCP server, and never sees a value. Vortex asks you once per key per session.
- **Keyboard cleaning**: lock every key while you wipe the keyboard.

Vortex speaks English and Ukrainian, and follows light and dark mode.

## Privacy
- Vortex works offline: no analytics, no auto-updates, no network access. Its only listener is the MCP server for Claude Code, on 127.0.0.1 only and guarded by a token.
- Your data stays in `~/Library/Application Support/Vortex`. Secrets stay in your login keychain.
- Text recognition runs on your Mac.

## Permissions
On first launch, Vortex walks you through the permissions it can use. Every one of them is optional:

| Permission | Used for |
| --- | --- |
| Notifications | the timer's end, Claude's key requests while the window is closed |
| Accessibility | keyboard cleaning |
| Screen Recording | tasks from the screen |

A feature whose permission is off shows a yellow warning. Click it to turn the permission on.

## Requirements
macOS 14 or later, on Apple silicon.

## Build from source
```sh
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig
make open
```
Set your team ID in `Config/Local.xcconfig` (a free Personal Team works), then press Run in Xcode. [CONTRIBUTING.md](CONTRIBUTING.md) has the commands, the architecture and the QA mode.

## Claude Code
In Vortex, open **Keys** and press **Connect**, or run the command it shows you once in Terminal. Claude Code then lists your keys by name and can use them in commands.

## License
[MIT](LICENSE)
